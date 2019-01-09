require "msgpack"

# Powerful framework for modern applications. See [onyxframework.org](https://onyxframework.org).
class Onyx
  # A basic event to inherit from.
  #
  # According to [Wikipedia](https://en.wikipedia.org/wiki/Event-driven_architecture#Event_flow_layers):
  #
  # > a significant temporal state or fact
  #
  # Code example:
  #
  # ```
  # # Abstract events are real.
  # abstract struct AbstractEvent < Onyx::Event
  # end
  #
  # struct MyEvent < AbstractEvent
  # end
  #
  # channel.subscribe(AbstractEvent) { |event| puts "Got AbstractEvent" }
  # channel.subscribe(MyEvent) { |event| puts "Got MyEvent" }
  #
  # channel.send(MyEvent.new)
  #
  # # Got AbstractEvent
  # # Got MyEvent
  # ```
  abstract struct Event
    include MessagePack::Serializable
    include MessagePack::Serializable::Strict

    macro inherited
      {% if @type.abstract? %}
        macro finished
          # Return this abstract event descendants.
          def self.descendants : Tuple
            { \{{@type.all_subclasses.map{ |t| "#{t}.as(Onyx::Event.class)" }.join(", ").id}} }
          end
        end
      {% else %}

        # Return `{ self }`.
        def self.descendants : Tuple
          { {{@type}}.as(Onyx::Event.class) }
        end
      {% end %}
    end
  end
end
