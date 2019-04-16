require "./channel/subscription"
require "./channel/duplicate_consumer_error"
require "./channel/memory"

module Onyx::EDA
  # An abstract event channel.
  # It implements basic logic used in other channels.
  abstract class Channel
    # Emit *events* returning themselves.
    # This method usually blocks until all events are delivered,
    # but the subscription block calls happen asynchronously.
    abstract def emit(events : Enumerable) : Enumerable

    # ditto
    abstract def emit(*events) : Enumerable

    # Emit *event* returning itself.
    # This method usually blocks until the event is delivered,
    # but the subscription block calls happen asynchronously.
    abstract def emit(event : T) : T forall T

    # Subscribe to an *event*. Returns a `Subscription` instance, which can be cancelled.
    # Every subscription instance gets notified about an `#emit`ted event.
    #
    # This is a non-blocking method, as it spawns a subscription fiber.
    #
    # ```
    # record MyEvent, payload : String do
    #   include Onyx::EDA::Event
    # end
    #
    # sub = channel.subscribe(MyEvent) do |event|
    #   puts event.payload
    # end
    #
    # channel.emit(MyEvent.new("foo"))
    #
    # # Need to yield the control
    # sleep(0.1)
    #
    # # Can cancel afterwards
    # sub.unsubscribe
    # ```
    #
    # You can *filter* the events by their getters, for example:
    #
    # ```
    # channel.subscribe(MyEvent, payload: "bar") do |event|
    #   puts event.payload # Would only output events with "bar" payload
    # end
    #
    # channel.emit(MyEvent.new("foo")) # Would not trigger the above subscription
    # ```
    #
    # See `Subscriber` for an includable subscribing module.
    abstract def subscribe(event : T.class, **filter, &block : T -> _) : Subscription(T) forall T

    # Begin consuming an *event*. Consumption differs from subscription in a way that
    # only a single consuming subscription instance with certain *consumer_id* among
    # all this channel subscribers would be notified about an event after it
    # successfully acquires a lock. The lock implementation differs in channels.
    #
    # Returns a `Subscription` instance. May raise `DuplicateConsumerError` if a
    # duplicate consumer ID found for this event in this very process.
    #
    # This is a non-blocking method, as it spawns a subscription fiber.
    #
    # ```
    # record MyEvent, payload : String do
    #   include Onyx::EDA::Event
    # end
    #
    # channel = Onyx::EDA::Channel::Redis.new
    #
    # sub = channel.subscribe(MyEvent, "MyConsumer") do |event|
    #   puts event.payload
    # end
    # ```
    #
    # Launch two subscribing processes, then emit an event in another process:
    #
    # ```
    # # Only one consumer of the two above will be notified
    # channel.emit(MyEvent.new("foo"))
    # ```
    #
    # See `Consumer` for an includable consumption module.
    abstract def subscribe(event : T.class, consumer_id : String, &block : T -> _) : Subscription(T) forall T

    # Cancel a *subscription*. Returns a boolean value indicating whether was it
    # successufully cancelled or not (for instance, it may be already cancelled,
    # returning `false`).
    abstract def unsubscribe(subscription : Subscription) : Bool

    # Wait for an *event* to happen, returning the *block* execution result.
    # An event can be *filter*ed by its getters.
    #
    # It is a **blocking** method.
    #
    # ```
    # record MyEvent, payload : String do
    #   include Onyx::EDA::Event
    # end
    #
    # # Will block the execution unless MyEvent is received with "foo" payload
    # payload = channel.await(MyEvent, payload: "foo") do |event|
    #   event.payload
    # end
    #
    # # In another fiber...
    # channel.emit(MyEvent.new("foo"))
    # ```
    #
    # This method can be used within the `select` block. It works better with the [timer.cr](https://github.com/vladfaust/timer.cr) shard.
    #
    # ```
    # select
    # when payload = channel.await(MyEvent, &.payload)
    #   puts payload
    # when Timer.new(30.seconds)
    #   raise "Timeout!"
    # end
    # ```
    def await(
      event : T.class,
      **filter,
      &block : T -> U
    ) : U forall T, U
      await_channel(T, **filter, &block).receive
    end

    # The same as block-version, but returns an *event* instance itself.
    #
    # ```
    # event = channel.await(MyEvent)
    # ```
    #
    # This method can be used within the `select` block. It works better with the [timer.cr](https://github.com/vladfaust/timer.cr) shard:
    #
    # ```
    # select
    # when event = channel.await(MyEvent)
    #   puts event.payload
    # when Timer.new(30.seconds)
    #   raise "Timeout!"
    # end
    # ```
    def await(event, **filter)
      await(event, **filter, &.itself)
    end

    protected abstract def acquire_lock?(event : T, consumer_id : String, timeout : Time::Span) : Bool forall T

    # Event hash -> Array(Subscription)
    @subscriptions = Hash(UInt64, Array(Void*)).new

    # Event hash -> ID -> Subscription
    @consumers = Hash(UInt64, Hash(String, Void*)).new

    protected def emit_impl(events : Enumerable(T)) : Enumerable(T) forall T
      {% raise "Can only emit non-abstract event objects (given `#{T}`)" unless (T < Reference || T < Struct) && !T.abstract? && !T.union? %}

      if subscriptions = @subscriptions[T.hash]?
        subscriptions.each do |void|
          subscription = Box(Subscription(T)).unbox(void)

          events.each do |event|
            subscription.notify(event)
          end
        end
      end

      if consumers = @consumers[T.hash]?
        consumers.each do |_, void|
          subscription = Box(Subscription(T)).unbox(void)

          events.each do |event|
            subscription.notify(event)
          end
        end
      end

      events
    end

    protected def emit_impl(*events : *T) : Enumerable forall T
      {% for t in T %}
        ary = Array({{t}}).new

        events.each do |event|
          if event.is_a?({{t}})
            ary << event
          end
        end

        emit_impl(ary)
      {% end %}

      events
    end

    protected def subscribe_impl(
      event : T.class,
      **filter : **U,
      &block : T -> _
    ) : Subscription(T) forall T, U
      subscription = Subscription(T).new(self, **filter, &block)
      void = Box(Subscription(T)).box(subscription)
      (@subscriptions[T.hash] ||= Array(Void*).new).push(void)
      return subscription
    end

    protected def subscribe_impl(
      event : T.class,
      consumer_id : String,
      &block : T -> _
    ) : Subscription(T) forall T, U
      {% raise "Can only subscribe to non-abstract event objects (given `#{T}`)" unless (T < Reference || T < Struct) && !T.abstract? && !T.union? %}

      existing = @consumers[T.hash]?.try &.[consumer_id]?
      raise DuplicateConsumerError.new(T, consumer_id) if existing

      channel = self

      subscription = Subscription(T).new(self, consumer_id) do |event|
        if channel.acquire_lock?(event, consumer_id)
          block.call(event)
        end
      end

      (@consumers[T.hash] ||= Hash(String, Void*).new)[consumer_id] = Box(Subscription(T)).box(subscription)

      return subscription
    end

    protected def unsubscribe_impl(subscription : Subscription(T)) : Bool forall T
      subscription.cancel

      if consumer_id = subscription.consumer_id
        return !!@consumers[T.hash]?.try(&.delete(consumer_id))
      else
        ary = @subscriptions[T.hash]?
        return false unless ary

        index = ary.index do |element|
          Box(Subscription(T)).unbox(element) == subscription
        end

        deleted = index ? !!ary.delete_at(index) : false

        if deleted && ary.empty?
          @subscriptions.delete(T.hash)
        end

        return deleted
      end
    end

    # :nodoc:
    def await_select_action(
      event : T.class,
      **filter,
      &block : T -> _
    ) forall T
      await_channel(event, **filter, &block).receive_select_action
    end

    # :nodoc:
    def await_select_action(event, **filter)
      await_select_action(event, **filter, &.itself)
    end

    protected def await_channel(
      event klass : T.class,
      **filter,
      &block : T -> U
    ) : ::Channel(U) forall T, U
      result_channel = ::Channel(U).new

      subscribe(T, **filter) do |event|
        result_channel.send(block.call(event))
      end

      result_channel
    end

    # Return an event object by its `Object#hash`.
    protected def hash_to_event_type(hash : UInt64)
      {% begin %}
        case hash
        {% for type in Object.all_subclasses.select { |t| t <= Onyx::EDA::Event && (t < Reference || t < Struct) && !t.abstract? } %}
          when {{type}}.hash then {{type}}
        {% end %}
        else
          raise "BUG: Unknown hash #{hash}"
        end
      {% end %}
    end
  end
end
