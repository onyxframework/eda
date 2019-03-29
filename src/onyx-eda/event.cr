require "uuid"

# A basic event module to include.
#
# According to [Wikipedia](https://en.wikipedia.org/wiki/Event-driven_architecture#Event_flow_layers):
#
# > a significant temporal state or fact
#
# Code example:
#
# ```
# struct MyEvent
#   include Onyx::EDA::Event
#
#   getter foo
#
#   def initialize(@foo : String)
#   end
# end
#
# channel.subscribe(MyEvent) do |event|
#   puts event.foo
# end
#
# event = channel.emit(MyEvent.new)
# pp event.event_id # => <UUID>
#
# sleep # You need to yield the control, see more in Channel docs
# ```
module Onyx::EDA::Event
  @event_id : UUID = UUID.random

  # This event ID. Defaults to a random `UUID`.
  getter event_id : UUID
end
