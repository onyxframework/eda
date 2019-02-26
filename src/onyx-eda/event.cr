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
# channel.subscribe(Object, MyEvent) do |event|
#   puts event.foo
# end
#
# spawn channel.send(MyEvent.new)
#
# sleep # You need to yield the control, see more in Channel docs
# ```
module Onyx::EDA::Event
  macro included
    {% unless @type < Struct || @type < Reference %}
      {% raise "Cannot include Onyx::EDA::Event to a module yet. Make #{@type} an abstract struct or class instead" %}
    {% end %}
  end
end
