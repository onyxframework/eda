require "mini_redis"
require "msgpack"
require "uuid"

require "../channel"

module Onyx::EDA
  module Event
    macro included
      include MessagePack::Serializable
    end
  end

  # A Redis event channel. It relies on [Redis streams](https://redis.io/topics/streams-intro),
  # thus requiring Redis version >= 5.
  #
  # It works exactly the same as the parent `Channel`, but instead of memory it uses Redis.
  # It spawns the redis subscription routine right after initialization, in a separate fiber.
  #
  # ```
  # channel = Onyx::EDA::Channel::Redis.new(ENV["REDIS_URL"])
  #
  # channel.subscribe(Object, MyEvent) do |event|
  #   pp event
  # end
  #
  # channel.unsubscribe(Object, MyEvent)
  # ```
  class Channel::Redis < Channel
    @client_id : Int64
    @blocked : Bool = false
    @subscription_redis_keys : Set(String) = Set(String).new

    # Initialize with Redis *uri* and Redis *namespace*.
    def self.new(uri : URI, namespace : String = "onyx-eda")
      new(MiniRedis.new(uri), MiniRedis.new(uri), namespace)
    end

    # ditto
    def self.new(uri : String, namespace : String = "onyx-eda")
      new(MiniRedis.new(URI.parse(uri)), MiniRedis.new(URI.parse(uri)), namespace)
    end

    # Explicitly initialize with two [`MiniRedis`](https://github.com/vladfaust/mini_redis)
    # instances and Redis *namespace*.
    def initialize(
      @redis : MiniRedis = MiniRedis.new,
      @sidekick : MiniRedis = MiniRedis.new,
      @namespace : String = "onyx-eda"
    )
      @client_id = @redis.command("CLIENT ID").raw.as(Int64)

      spawn do
        routine
      end
    end

    # See `Channel#emit`.
    def emit(events : Enumerable(T)) forall T
      response = @sidekick.transaction do |tx|
        events.each do |event|
          tx.send(
            "XADD",
            "#{@namespace}:#{event.class.to_s.split("::").map(&.underscore).join('-')}",
            "*",
            "pld",
            event.to_msgpack,
          )
        end
      end

      response.raw.as(Array).map { |v| String.new(v.raw.as(Bytes)) }
    end

    # See `Channel#subscribe`.
    def subscribe(object, event : T.class, &proc : T -> Nil) : Enumerable(String) forall T
      changed = super(object, event, &proc)
      unblock_client unless changed.empty?
      changed.map { |k| event_redis_key(k) }
    end

    # See `Channel#unsubscribe`.
    def unsubscribe(object, event : T.class, &proc : T -> Nil) : Enumerable(String) forall T
      changed = super
      unblock_client unless changed.empty?
      changed.map { |k| event_redis_key(k) }
    end

    # ditto
    def unsubscribe(object, event : T.class) : Enumerable(String) forall T
      changed = super
      unblock_client unless changed.empty?
      changed.map { |k| event_redis_key(k) }
    end

    # ditto
    def unsubscribe(object) : Enumerable(String)
      changed = super
      unblock_client unless changed.empty?
      changed.map { |k| event_redis_key(k) }
    end

    protected def event_redis_key(klass : String)
      klass.split("::").map(&.underscore).join('-')
    end

    protected def routine
      # The exact time to read messages since,
      # because "$" IDs with multiple stream keys
      # will lead to a single stream reading
      now = (Time.now.to_unix_ms - 1).to_s

      # Cache for last read message IDs
      last_read_ids = Hash(String, String).new

      loop do
        # Dupping the `#events_to_subscribe` array because it can change in runtime
        streams = @subscriptions.keys.map(&.split("::").map(&.underscore).join('-'))

        if streams.empty?
          # If there are no events to subscribe to, then just block
          #

          begin
            @blocked = true
            @redis.command("BLPOP #{UUID.random} 0")
          rescue ex : MiniRedis::Error
            if ex.message =~ /^UNBLOCKED/
              next @blocked = false
            else
              raise ex
            end
          end
        end

        # Update the client name so others know which streams is this client reading
        @redis.pipeline do |pipe|
          pipe.send("CLIENT SETNAME #{@namespace}:channel:#{streams.join(',')}")
        end

        loop do
          begin
            @blocked = true

            response = @redis.command(
              "XREAD COUNT 1 BLOCK 0 STREAMS " +
              streams.map { |s| "#{@namespace}:#{s}" }.join(' ') + ' ' +
              streams.map { |s| last_read_ids.fetch(s) { now } }.join(' ')
            )
          rescue ex : MiniRedis::Error
            if ex.message =~ /^UNBLOCKED/
              break @blocked = false
            else
              raise ex
            end
          end

          parse_xread(response) do |stream, message_id|
            last_read_ids[stream] = message_id
          end
        end
      end
    end

    # Parse the `XREAD` response, yielding events one-by-one.
    protected def parse_xread(response, &block)
      response.raw.as(Array).each do |entry|
        stream_name = String.new(entry.raw.as(Array)[0].raw.as(Bytes)).match(/#{@namespace}:(.+)/).not_nil![1]

        {% begin %}
          case stream_name
          {% for type in Object.all_subclasses.select { |t| t < Onyx::EDA::Event && !t.abstract? } %}
            when {{type.stringify.split("::").map(&.underscore).join('-')}}
              entry.raw.as(Array)[1].raw.as(Array).each do |message|
                redis_message_id = String.new(message.raw.as(Array)[0].raw.as(Bytes))

                args = message.raw.as(Array)[1].raw.as(Array)
                payload_index = args.map{ |v| String.new(v.raw.as(Bytes)) }.index("pld").not_nil! + 1
                payload = args[payload_index].raw.as(Bytes)

                event = {{type}}.from_msgpack(payload)

                spawn notify(event.as({{type}}))

                yield stream_name, redis_message_id
              end
          {% end %}
          end
        {% end %}
      end
    end

    # Unblock the subscribed client.
    protected def unblock_client
      @sidekick.command("CLIENT UNBLOCK #{@client_id} ERROR") if @blocked
    end
  end
end
