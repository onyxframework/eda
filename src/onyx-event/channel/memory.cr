require "../channel"

class Onyx
  abstract struct Event
    abstract class Channel
      # A non-blocking in-memory `Event::Channel` implementation.
      # It relies on Crystal `::Channel`s.
      #
      # ```
      # require "onyx-event/channel/memory"
      #
      # # Subscriptions routine is spawned immediately
      # channel = Onyx::Event::Channel::Memory.new
      #
      # channel.subscribe(MyEvent) do |event|
      #   puts "Got #{event}"
      # end
      #
      # # Don't forget to sleep, otherwise the process exits
      # sleep
      # ```
      class Memory < Channel
        # A Crystal `::Channel` associated with this event channel.
        getter channel

        def initialize(@channel : ::Channel(Event) = ::Channel(Event).new)
          spawn do
            loop do
              notify(@channel.receive)
            end
          end
        end

        # Send the *event* to the `#channel`.
        def send(event : Event)
          @channel.send(event)
        end

        # Send multiple *events* to the `#channel`.
        def send(events : Enumerable(Event))
          events.each do |event|
            @channel.send(event)
          end
        end

        def subscribe(event : T.class, &proc : Proc(T, Nil)) : Bool forall T
          _subscribe(event, &proc)
        end

        def unsubscribe(event : T.class, &proc : Proc(T, Nil)) : Bool forall T
          _unsubscribe(event, &proc)
        end

        def unsubscribe(event : T.class) : Bool forall T
          _unsubscribe(event)
        end
      end
    end
  end
end
