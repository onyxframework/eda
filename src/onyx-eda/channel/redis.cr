require "mini_redis"
require "msgpack"

require "../channel"
require "../ext/uuid/msgpack"

{% for type in Object.all_subclasses.select { |t| t <= Onyx::EDA::Event && !t.abstract? } %}
  {% if type < Struct %}
    struct {{type}}
  {% elsif type < Reference %}
    class {{type}}
  {% end %}
    include MessagePack::Serializable

    def self.to_redis_key : String
      {{type.stringify.split("::").map(&.underscore).join(":")}}
    end
  end
{% end %}

module Onyx::EDA
  module Event
    macro included
      include MessagePack::Serializable

      # Get a Redis key for this event. Currently formats like this:
      #
      # ```
      # Namespace::MyEvent => "namespace:my_event"
      # ```
      def self.to_redis_key : String
        self.to_s.split("::").map(&.underscore).join(":")
      end
    end
  end

  # A Redis channel. All subscribers to the same Redis instance receive notifications
  # about events emitted within this channel, which leads to an easy distribution.
  #
  # NOTE: It relies on Redis streams feature, which **requires Redis version >= 5**!
  #
  # In Onyx::EDA events are delivered unreliably and in real-time, which means that
  # fresh subscribers do not have access to recent events, only to the future ones.
  # That's why consumption is implemented with locks instead of consumer groups.
  #
  # All events are serialized with [MessagePack](https://github.com/crystal-community/msgpack-crystal).
  #
  # ```
  # # Process #1
  # require "onyx-eda/channel/redis"
  #
  # record MyEvent, payload : String do
  #   include Onyx::EDA::Event
  # end
  #
  # channel = Onyx::EDA::Channel::Redis.new("redis://localhost:6379")
  # channel.emit(MyEvent.new("foo"))
  # ```
  #
  # ```
  # # Process #2
  # require "onyx-eda/channel/redis"
  #
  # record MyEvent, payload : String do
  #   include Onyx::EDA::Event
  # end
  #
  # channel = Onyx::EDA::Channel::Redis.new("redis://localhost:6379")
  # channel.subscribe(MyEvent) do |event|
  #   puts event.payload
  #   exit
  # end
  #
  # sleep
  # ```
  class Channel::Redis < Channel
    @client_id : Int64
    @blocked : Bool = false
    @siphash_key = StaticArray(UInt8, 16).new(0)

    # Initialize with Redis *uri* and Redis *namespace*.
    # *args* and *nargs* are passed directly to a `MiniRedis` instance.
    def self.new(uri : URI, namespace : String = "onyx-eda", *args, **nargs)
      new(
        MiniRedis.new(uri, *args, **nargs),
        MiniRedis.new(uri, *args, **nargs),
        namespace
      )
    end

    # ditto
    def self.new(uri : String, namespace : String = "onyx-eda", *args, **nargs)
      new(
        MiniRedis.new(URI.parse(uri), *args, **nargs),
        MiniRedis.new(URI.parse(uri), *args, **nargs),
        namespace
      )
    end

    # Explicitly initialize with two [`MiniRedis`](https://github.com/vladfaust/mini_redis)
    # instances (one would block-read and another would issue commands)
    # and Redis *namespace*.
    def initialize(
      @redis : MiniRedis,
      @sidekick : MiniRedis,
      @namespace : String = "onyx-eda"
    )
      @client_id = @redis.send("CLIENT", "ID").raw.as(Int64)
      spawn routine
      spawn unblocking_routine
    end

    # Emit *events*, sending them to an appropriate stream. See `Channel#emit`.
    # The underlying `XADD` command has `MAXLEN ~ 1000` option.
    #
    # This method **blocks** until all subscribers to this event read it from the stream.
    #
    # TODO: Allow to change `MAXLEN`.
    def emit(
      events : Enumerable(T),
      redis : MiniRedis = @sidekick
    ) : Enumerable(T) forall T
      {% raise "Can only emit non-abstract event objects (given `#{T}`)" unless (T < Reference || T < Struct) && !T.abstract? && !T.union? %}

      stream = T.to_redis_key

      proc = ->(r : MiniRedis) do
        events.each do |event|
          r.send(
            "XADD",
            @namespace + ':' + stream,
            "MAXLEN",
            "~",
            1000,
            "*",
            "pld",
            event.to_msgpack,
          )
        end
      end

      if redis.transaction?
        response = proc.call(redis)
      else
        response = redis.transaction(&proc)
      end

      events
    end

    # ditto
    def emit(*events : *T) : Enumerable forall T
      @sidekick.transaction do |tx|
        {% for t in T %}
          ary = Array({{t}}).new

          events.each do |event|
            if event.is_a?({{t}})
              ary << event
            end
          end

          emit(ary, tx)
        {% end %}
      end

      events
    end

    # See `#emit(events)`.
    def emit(event : T) : T forall T
      emit({event}).first
    end

    # Subscribe to an *event* reading from its stream.
    # You should yield the control to actually start reading.
    # See `Channel#subscribe(event, **filter, &block)`.
    def subscribe(
      event : T.class,
      **filter,
      &block : T -> _
    ) : Subscription forall T
      wrap_changes do
        subscribe_impl(T, **filter, &block)
      end
    end

    # Begin consuming an *event* reading from its stream. It is guaranteed that
    # only a **single** consuming subscription with given *id* accross the whole
    # application would be notified about an event.
    #
    # But such notifications are non-reliable, i.e. a single consumer
    # could crash during event handling, meaning that this event would not be handled
    # properly. If you need reliability, use a background job processing istead,
    # for example, [Worcr](https://worcr.com).
    #
    # See `Channel#subscribe(event, consumer_id, &block)`.
    def subscribe(
      event : T.class,
      consumer_id : String,
      &block : T -> _
    ) : Subscription forall T
      wrap_changes do
        subscribe_impl(T, consumer_id, &block)
      end
    end

    # See `Channel#unsubscribe`.
    def unsubscribe(subscription : Subscription) : Bool
      wrap_changes { unsubscribe_impl(subscription) }
    end

    protected def acquire_lock?(
      event : T,
      consumer_id : String,
      timeout : Time::Span = 5.seconds
    ) : Bool forall T
      key = "#{@namespace}:lock:#{T.to_redis_key}:#{consumer_id}:#{event.event_id.hexstring}"

      response = @sidekick.send(
        "SET", key, "t",
        "PX", (timeout.total_seconds * 1000).round.to_i,
        "NX"
      )

      return !response.raw.nil?
    end

    # Wrap (un)subscribing, checking if the list of watched events changed.
    # This could trigger the main client unblocking.
    protected def wrap_changes(&block)
      before = (@subscriptions.keys + @consumers.keys).uniq!

      yield.tap do
        want_unblock if before != (@subscriptions.keys + @consumers.keys).uniq!
      end
    end

    protected def routine
      # The exact time to read messages since,
      # because "$" IDs with multiple stream keys
      # will lead to a single stream reading
      now = (Time.now.to_unix_ms - 1).to_s

      # Cache for last read message IDs
      last_read_ids = Hash(String, String).new

      loop do
        streams = (@subscriptions.keys + @consumers.keys).uniq!.map do |hash|
          hash_to_event_type(hash).to_redis_key
        end

        if streams.empty?
          # If there are no events to subscribe to, then just block
          #

          begin
            @blocked = true
            @redis.send("BLPOP", UUID.random.bytes.to_slice, 0)
          rescue ex : MiniRedis::Error
            if ex.message =~ /^UNBLOCKED/
              next @blocked = false
            else
              raise ex
            end
          end
        end

        loop do
          begin
            @blocked = true

            commands = ["XREAD", "COUNT", 1, "BLOCK", 0, "STREAMS"]
            commands.concat(streams.map { |s| @namespace + ':' + s })
            commands.concat(streams.map { |s| last_read_ids.fetch(s) { now } })

            response = @redis.send(commands)
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
            when {{type.stringify.split("::").map(&.underscore).join(':')}}
              entry.raw.as(Array)[1].raw.as(Array).each do |message|
                redis_message_id = String.new(message.raw.as(Array)[0].raw.as(Bytes))

                args = message.raw.as(Array)[1].raw.as(Array)
                payload_index = args.map{ |v| String.new(v.raw.as(Bytes)) }.index("pld").not_nil! + 1
                payload = args[payload_index].raw.as(Bytes)

                event = {{type}}.from_msgpack(payload)
                emit_impl({event})

                yield stream_name, redis_message_id
              end
          {% end %}
          end
        {% end %}
      end
    end

    @unblock_channel = ::Channel(Nil).new(1)

    protected def unblocking_routine
      loop do
        @unblock_channel.receive

        if @blocked
          @sidekick.send("CLIENT", "UNBLOCK", @client_id, "ERROR")
          @blocked = false
        end
      end
    end

    # Unblock the subscribed client.
    protected def want_unblock
      spawn do
        @unblock_channel.send(nil) unless @unblock_channel.full?
      end
    end
  end
end
