require "../onyx-event"

class Onyx
  abstract struct Event
    # An abstract event channel.
    #
    # According to [Wikipedia](https://en.wikipedia.org/wiki/Event-driven_architecture#Event_channel):
    #
    # > An event channel is a mechanism of propagating the information collected
    # from an event generator to the event engine ... The events are stored in a queue,
    # waiting to be processed later by the event processing engine.
    #
    # Currently implemented channels: `Channel::Redis` and `Channel::Memory`.
    #
    # A channel usually begins its routines upon initialization in separate fibers,
    # thus being non-blocking.
    abstract class Channel
      # Send *event* to this channel, triggering its subscribers.
      abstract def send(event : Event)

      # Send multiple *events* to this channel, triggering its subscribers.
      abstract def send(events : Enumerable(Event))

      # Subscribes *proc* to *event*.
      # Returns `true` in case of success, i.e. it hasn't been already subscribed.
      #
      # ```
      # channel.subscribe(MyEvent) do |event|
      #   pp! typeof(event) # => MyEvent
      # end
      # ```
      abstract def subscribe(event : T.class, &proc : Proc(T, Nil)) : Bool forall T

      protected def _subscribe(event : T.class, &proc : Proc(T, Nil)) : Bool forall T
        set = @subscribers[event]?

        unless set
          set = Set(Tuple(Void*, Void*)).new
          @subscribers[event] = set
        end

        tuple = {proc.pointer, proc.closure_data}

        !!unless set.includes?(tuple)
          set << tuple
        end
      end

      # Unsubscribe a *proc* subscriber from *event*.
      # Returns `false` if such a subscriber is not in the subscribers list
      # (probably has already been unsubscribed or never been at all).
      #
      # ```
      # proc = ->(event : MyEvent) { puts "Got MyEvent!" }
      #
      # channel.subscribe(MyEvent, &proc)   # => true
      # channel.subscribe(MyEvent, &proc)   # => false
      # channel.unsubscribe(MyEvent, &proc) # => true
      # channel.unsubscribe(MyEvent, &proc) # => false
      # ```
      abstract def unsubscribe(event : T.class, &proc : Proc(T, Nil)) : Bool forall T

      protected def _unsubscribe(event : T.class, &proc : Proc(T, Nil)) : Bool forall T
        set = @subscribers[event]?
        return false unless set

        tuple = {proc.pointer, proc.closure_data}

        result = !!if set.includes?(tuple)
          set.delete(tuple)
        end

        unless set.size > 0
          @subscribers.delete(event)
        end

        return result
      end

      # Unsubscribe **all** subscribers from *event*.
      # Returns `false` in case if there were no any subscribers to the event.
      #
      # ```
      # channel.unsubscribe(MyEvent) # => true
      # ```
      abstract def unsubscribe(event : T.class) : Bool forall T

      protected def _unsubscribe(event : T.class) : Bool forall T
        !!@subscribers.delete(event)
      end

      # Will only call subscribers' procs subscribed
      # to this particular *event* and or to its descendants.
      #
      # ```
      # abstract struct AbstractEvent < Onyx::Event
      # end
      #
      # struct BarEvent < AbstractEvent
      #   getter bar
      #
      #   def initialize(@bar : String)
      #   end
      # end
      #
      # channel.subscribe(BarEvent) do |event|
      #   puts "Got #{event.class}"
      # end
      #
      # channel.subscribe(AbstractEvent) do |event|
      #   puts "Got #{event.class}"
      # end
      #
      # channel.send(BarEvent.new)
      #
      # # Got AbstractEvent
      # # Got BarEvent
      # ```
      protected def notify(event : Event)
        matched = false

        {% for subclass in Event.all_subclasses %}
          if {{subclass}} === event
            matched = true

            @subscribers[{{subclass}}]?.try &.each do |(pointer, closure_data)|
              Proc({{subclass}}, Nil).new(pointer, closure_data).call(event.as({{subclass}}))
            end
          end
        {% end %}

        raise "BUG: Unknown event #{event.class}" unless matched
      end

      # Subscribers to this channel by `Event`.
      # Due to inability of storing `Proc(T)` as an instance variable,
      # its internal representation -- two pointers -- is used instead.
      @subscribers = Hash(Event.class, Set(Tuple(Void*, Void*))).new
    end
  end
end
