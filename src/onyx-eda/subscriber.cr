# A module which would make an including object an event subscriber.
# Subscribers are notified about every incoming event of type `T`.
#
# A single object can have multiple `Subscriber` and `Consumer` modules included,
# just make sure you have `#handle` method defined for each event.
#
# NOTE: You can not have **both** `Subscriber` and `Consumer` modules included for
# a single event type.
#
# A single actor instance (this module includes `Actor` module) can be subscribed to
# multiple channels simultaneously.
#
# TODO: Have an internal buffer to filter repeating (i.e. with the same ID) events
# among multiple channels.
#
# ```
# class Actor::Logger
#   include Onyx::EDA::Subscriber(Event::User::Registered)
#   include Onyx::EDA::Consumer(Event::Payment::Successfull)
#
#   # This method will be called in *all* Actor::Logger instances
#   def handle(event : Event::User::Registered)
#     log_into_terminal("New user with id #{event.id}")
#   end
#
#   # This method will be called in only *one* Actor::Logger instance
#   def handle(event : Event::Payment::Successfull)
#     send_email("admin@example.com", "New payment of $#{event.amount}")
#   end
# end
#
# actor = Actor::Logger.new
# actor.subscribe(channel) # Non-blocking method
# # ...
# actor.unsubscribe(channel)
# ```
module Onyx::EDA::Subscriber(T)
  include Actor

  @subscriptions = Hash(UInt64, Hash(UInt64, Void*)).new

  # Handle incoming event. Must be defined explicitly in a consumer.
  # TODO: Find a way to enable per-event filtering.
  abstract def handle(event : T)

  macro included
    {% raise "Cannot include both Subscriber and Consumer modules for the same event `#{T}`" if @type < Onyx::EDA::Consumer(T) %}

    def subscribe(channel : Onyx::EDA::Channel) : self
      subscribe_impl(@subscriptions, {{T}}, {{!!@type.methods.find { |m| m.name == "subscribe" }}}) do
        channel.subscribe({{T}}) do |event|
          handle(event)
        end
      end
    end

    def unsubscribe(channel : Onyx::EDA::Channel) : self
      unsubscribe_impl(@subscriptions, {{T}}, {{!!@type.methods.find { |m| m.name == "unsubscribe" }}})
    end
  end
end
