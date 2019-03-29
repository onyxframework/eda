# A module which would make an including object an event consumer.
# Consumption differs from subscription in a way that only a single consumption
# instance with certain ID would be notified about an event.
# In this module, consumer ID equals to the including object class name.
#
# This module behaves a lot like `Subscriber`, see its docs for details.
module Onyx::EDA::Consumer(T)
  include Actor

  @consumers = Hash(UInt64, Hash(UInt64, Void*)).new

  # Handle incoming event. Must be defined explicitly in a consumer.
  # TODO: Find a way to enable per-event custom ID.
  abstract def handle(event : T)

  macro included
    {% raise "Cannot include both Subscriber and Consumer modules for the same event `#{T}`" if @type < Onyx::EDA::Subscriber(T) %}

    def subscribe(channel : Onyx::EDA::Channel) : self
      subscribe_impl(@consumers, {{T}}, {{!!@type.methods.find { |m| m.name == "subscribe" }}}) do
        channel.subscribe({{T}}, {{@type.stringify.split("::").join(".")}}) do |event|
          handle(event)
        end
      end
    end

    def unsubscribe(channel : Onyx::EDA::Channel) : self
      unsubscribe_impl(@consumers, {{T}}, {{!!@type.methods.find { |m| m.name == "unsubscribe" }}})
    end
  end
end
