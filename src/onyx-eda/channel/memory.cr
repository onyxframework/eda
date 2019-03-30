require "../channel"

module Onyx::EDA
  # An in-memory channel. Emitted events are visible within current process only.
  class Channel::Memory < Channel
    def emit(events : Enumerable(T)) : Enumerable(T) forall T
      emit_impl(events)
    end

    def emit(*events : *T) : Enumerable forall T
      emit_impl(*events)
    end

    def emit(event : T) : T forall T
      emit_impl(event).first
    end

    def subscribe(
      event : T.class,
      **filter,
      &block : T -> _
    ) : Subscription(T) forall T
      subscribe_impl(event, **filter, &block)
    end

    def subscribe(
      event : T.class,
      consumer_id : String,
      **filter,
      &block : T -> _
    ) : Subscription(T) forall T
      subscribe_impl(event, consumer_id, **filter, &block)
    end

    def unsubscribe(subscription : Subscription) : Bool
      unsubscribe_impl(subscription)
    end

    protected def acquire_lock?(*args)
      true
    end
  end
end
