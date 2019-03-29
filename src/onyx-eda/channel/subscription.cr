require "./subscription/inactive_error"

abstract class Onyx::EDA::Channel
  # An event subscription instance. All subscribers are notified about an event unless
  # it doesn't match the filters.
  #
  # You should not initialize this class manually, use `Channel#subscribe` instead.
  # When you want to stop subscription, call the `#unsubscribe` method on a
  # `Subscription` instance or `Channel#unsubscribe`.
  class Subscription(T)
    @active = true

    # Whether is this subscription currently active.
    getter? active

    # Cancel this subscription.
    # May raise `InactiveError` if the subscription is currently not active
    # (i.e. already cancelled).
    def unsubscribe
      raise InactiveError.new unless @active
      @active = false
      @eda_channel.unsubscribe(self)
    end

    @eda_channel : Channel
    @consumer_id : String | Nil

    @event_channel = ::Channel(T).new
    @cancel_channel = ::Channel(Nil).new(1)

    @cancelled = false

    protected getter consumer_id

    # :nodoc:
    protected def initialize(
      @eda_channel : Channel,
      @consumer_id : String? = nil,
      **filter : **U,
      &block : T -> V
    ) : self forall U, V
      spawn do
        loop do
          select
          when event = @event_channel.receive
            {% for k, v in U %}
              next unless event.{{k.id}} == filter[{{k.stringify}}].as({{v}})
            {% end %}

            spawn block.call(event)
          when @cancel_channel.receive
            break
          end
        end
      end

      self
    end

    protected def notify(event : T)
      raise InactiveError.new unless @active
      @event_channel.send(event)
    end

    protected def cancel
      @cancel_channel.send(nil) unless @cancelled
      @cancelled = true
    end
  end
end
