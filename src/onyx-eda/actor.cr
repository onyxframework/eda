# A module which turns an object into event actor.
# It is included into `Subscriber` and `Consumer` modules.
module Onyx::EDA::Actor
  @subscribed_channels = Array(Onyx::EDA::Channel).new

  # Subscribe to a *channel*.
  # Raises if this actor is already subsribed to this channel.
  # Returns self.
  def subscribe(channel : Onyx::EDA::Channel) : self
    raise "Already subscribed to #{channel}" if @subscribed_channels.includes?(channel)
    @subscribed_channels.push(channel)
    self
  end

  # Unsubscribe from a *channel*. Raises if this actor is already
  # unsubscribed or not subscribed to this channel yet. Return self.
  def unsubscribe(channel : Onyx::EDA::Channel) : self
    raise "Not subscribed to #{channel} yet" unless @subscribed_channels.includes?(channel)
    @subscribed_channels.delete(channel)
    self
  end

  private macro subscribe_impl(var, t, has_method, &block)
    {% if has_method %}
      previous_def
    {% else %}
      super
    {% end %}

    subscription = ({{yield.id}})

    channel_hash = {{var}}[channel.hash] ||= Hash(UInt64, Void*).new
    channel_hash[{{t}}.hash] = Box(Onyx::EDA::Channel::Subscription({{t}})).box(subscription.as(Onyx::EDA::Channel::Subscription({{t}})))

    self
  end

  private macro unsubscribe_impl(var, t, has_method)
    {% if has_method %}
      previous_def
    {% else %}
      super
    {% end %}

    channel_hash = {{var}}[channel.hash]
    void = channel_hash.delete({{t}}.hash)
    subscription = Box(Onyx::EDA::Channel::Subscription({{t}})).unbox(void.not_nil!)
    subscription.unsubscribe

    if channel_hash.empty?
      {{var}}.delete(channel_hash)
    end

    self
  end
end
