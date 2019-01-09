require "redis"

require "../channel"
require "../ext/redis/commands"

class Onyx
  abstract struct Event
    abstract class Channel
      # A non-blocking `::Redis` `Event::Channel` implementation.
      # It relies on [Redis Streams](https://redis.io/topics/streams-intro).
      #
      # It creates two `::Redis` clients on initilization.
      #
      # ```
      # require "onyx-event/channel/redis"
      #
      # # Subscriptions routine is spawned immediately
      # channel = Onyx::Event::Channel::Redis.new(
      #   redis_proc: ->{ Redis.new(url: ENV["REDIS_URL"]) },
      #   namespace: "custom-namespace"
      # )
      #
      # channel.subscribe(MyEvent) do |event|
      #   puts "Got #{event}"
      # end
      #
      # # Don't forget to sleep, otherwise the process exits
      # sleep
      # ```
      class Redis < Channel
        # Initialize a new Redis channel with *redis_proc* to
        # initialize two new `::Redis` clients and also Redis *namespace*.
        #
        # * *batch* option defines how many messages to grab from an event stream per `XREAD`.
        def initialize(
          @redis_proc : Proc(::Redis) = ->{ ::Redis.new },
          @namespace : String = "onyx-event",
          *,
          batch : Int = 10
        )
          # Initialize sidekick Redis client for background tasks
          #

          @sidekick = @redis_proc.call
          @sidekick.pipelined { |pipe| pipe.client_setname("onyx-event-channel-sidekick") }

          # Begin the routine in a separate fiber
          #

          spawn subscriptions_routine(batch)
        end

        # Add the *event* to the Redis stream using `::Redis::Commands#xadd`.
        def send(event : Event, client = @sidekick)
          client.xadd(
            "#{@namespace}:#{event.to_redis_key}",
            '*',
            "arg",
            String.new(event.to_msgpack)
          )
        end

        # Add multiple *events* to the Redis stream using `::Redis::Commands#xadd`.
        # This method uses [pipelining](http://stefanwille.github.io/crystal-redis/Redis/PipelineApi.html) for improved performance.
        def send(events : Enumerable(Event))
          @sidekick.pipelined do |pipe|
            events.each do |event|
              send(event, pipe)
            end
          end
        end

        def subscribe(event : T.class, &proc : Proc(T, Nil)) : Nil forall T
          break_subscribe_routine?(events_to_subscribe_size, _subscribe(event, &proc))
        end

        def unsubscribe(event : T.class, &proc : Proc(T, Nil)) : Bool forall T
          break_subscribe_routine?(events_to_subscribe_size, _unsubscribe(event, &proc))
        end

        def unsubscribe(event : T.class) : Bool forall T
          break_subscribe_routine?(events_to_subscribe_size, _unsubscribe(event))
        end

        @sidekick : ::Redis
        @subscriber_client_id : Int64?

        protected def subscriptions_routine(batch : Int = 10)
          # Initialize a subscriber Redis client to read from streams
          #

          subscriber = @redis_proc.call

          client_id, _ = subscriber.multi do |multi|
            multi.client_id
            multi.client_setname("onyx-event-channel-subscriber:#{@namespace}:")
          end

          @subscriber_client_id = client_id.as(Int64)

          # The exact time to read messages since,
          # because "$" IDs with multiple stream keys
          # will lead to a single stream reading
          now = Time.now.to_unix_ms.to_s

          # Cache for last read message IDs
          last_read_ids = Hash(Event.class, String).new

          loop do
            # Dupping the `#events_to_subscribe` array because it can change in runtime
            events = events_to_subscribe.dup

            if events_to_subscribe.empty?
              # If there are no events to subscribe to, then just block
              #

              begin
                subscriber.blpop(["onyx-event-unexisting-list-to-block"], 0)
              rescue ex : ::Redis::Error
                if ex.message =~ /^UNBLOCKED/
                  next
                else
                  raise ex
                end
              end
            end

            # Update the client name so others know which streams is this client reading
            subscriber.pipelined do |pipe|
              streams = events.map(&.to_redis_key)
              pipe.client_setname("onyx-event-channel-subscriber:#{@namespace}:#{streams.join(',')}")
            end

            response = begin
              subscriber.xread(
                count: batch,
                block: 0,
                streams: events.map { |e| "#{@namespace}:#{e.to_redis_key}" },
                id: events.map { |event| last_read_ids.fetch(event) { now } }
              )
            rescue ex : ::Redis::Error
              if ex.message =~ /^UNBLOCKED/
                next
              else
                raise ex
              end
            end

            parse_xread(response.not_nil!) do |event|
              last_read_ids[event.class] = event.redis_message_id

              # BUG: If doing inline spawn, the compiler would crash.
              spawn do
                notify(event)
              end
            end
          end
        end

        # This method unblocks the subscriber client only if `#events_to_subscribe` changed.
        protected def break_subscribe_routine?(before_events_size before : Int, changed : Bool)
          if changed && @subscriber_client_id && before != events_to_subscribe.size
            @sidekick.client_unblock(@subscriber_client_id.not_nil!, true)
          end

          changed
        end

        # Parse the `XREAD` response, yielding events one-by-one.
        protected def parse_xread(response, &block)
          response.each do |entry|
            stream_name = entry.as(Array)[0].as(String).match(/#{@namespace}:(.+)/).not_nil![1]

            {% begin %}
              case stream_name
              {% for klass in Event.all_subclasses.reject { |k| k.abstract? } %}
                when {{klass.stringify.split("::").map(&.underscore).join('-')}}
                  entry.as(Array)[1].as(Array).each do |message|
                    redis_message_id = message.as(Array)[0].as(String)

                    args = message.as(Array)[1].as(Array)
                    arg_index = args.map(&.as(String)).index("arg").not_nil! + 1
                    arg = args[arg_index].as(String)

                    event = {{klass}}.from_msgpack(arg)
                    event.redis_message_id = redis_message_id

                    yield event
                  end
              {% end %}
              end
            {% end %}
          end
        end

        # events_to_subscribe* made for optimization purposes
        #

        @cached_subscribers_size : Int32? = nil
        @cached_events_to_subscribe : Array(Event.class)? = nil

        protected def events_to_subscribe_size
          if size = @cached_subscribers_size
            return size
          else
            events_to_subscribe.size
          end
        end

        protected def events_to_subscribe
          if @cached_subscribers_size &&
             @cached_events_to_subscribe &&
             @subscribers.keys.size == @cached_subscribers_size
            return @cached_events_to_subscribe.not_nil!
          else
            @cached_subscribers_size = @subscribers.keys.size
            @cached_events_to_subscribe = @subscribers.keys.flat_map(&.descendants.to_a).uniq
          end
        end
      end
    end
  end

  abstract struct Event
    @[MessagePack::Field(ignore: true)]
    @redis_message_id : String?

    # Return Redis stream message ID associated with this event.
    #
    # NOTE: Requires `Channel::Redis` to be required.
    getter! redis_message_id

    # :nodoc:
    setter redis_message_id

    # Convert self class name to a Redis stream key.
    # For example, `"Namespaced::FooEvent"` turns into `"namespaced-foo_event"`.
    #
    # NOTE: Requires `Channel::Redis` to be required.
    def self.to_redis_key : String
      {{@type.stringify.split("::").map(&.underscore).join('-')}}
    end

    # See `.to_redis_key`.
    #
    # NOTE: Requires `Channel::Redis` to be required.
    def to_redis_key : String
      self.class.to_redis_key
    end
  end
end
