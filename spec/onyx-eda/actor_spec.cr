require "../spec_helper"

module Onyx::EDA::Actor
  record TestEvent::A, payload : String do
    include Event
  end

  record TestEvent::B, payload : Int32 do
    include Event
  end

  class SimpleSubscriber
    include Onyx::EDA::Subscriber(TestEvent::A)

    class_getter latest_value : String? = nil

    def handle(event)
      @@latest_value = event.payload
    end
  end

  class DoubleSubscriber
    include Onyx::EDA::Subscriber(TestEvent::A)
    include Onyx::EDA::Subscriber(TestEvent::B)

    class_getter latest_value_a : String? = nil
    class_getter latest_value_b : Int32? = nil

    def handle(event : TestEvent::A)
      @@latest_value_a = event.payload
    end

    def handle(event : TestEvent::B)
      @@latest_value_b = event.payload
    end
  end

  class SimpleConsumer
    include Onyx::EDA::Subscriber(TestEvent::A)

    class_getter latest_value : String? = nil

    def handle(event)
      @@latest_value = event.payload
    end
  end

  class DoubleConsumer
    include Onyx::EDA::Consumer(TestEvent::A)
    include Onyx::EDA::Consumer(TestEvent::B)

    class_getter latest_value_a : String? = nil
    class_getter latest_value_b : Int32? = nil

    def handle(event : TestEvent::A)
      @@latest_value_a = event.payload
    end

    def handle(event : TestEvent::B)
      @@latest_value_b = event.payload
    end
  end

  class MixedActor
    include Onyx::EDA::Subscriber(TestEvent::A)
    include Onyx::EDA::Consumer(TestEvent::B)

    class_getter latest_value_a : String? = nil
    class_getter latest_value_b : Int32? = nil

    def handle(event : TestEvent::A)
      @@latest_value_a = event.payload
    end

    def handle(event : TestEvent::B)
      @@latest_value_b = event.payload
    end
  end

  describe self do
    channel = Onyx::EDA::Channel::Memory.new

    simple_subscriber = SimpleSubscriber.new
    simple_subscriber.subscribe(channel)

    double_subscriber = DoubleSubscriber.new
    double_subscriber.subscribe(channel)

    simple_consumer = SimpleConsumer.new
    simple_consumer.subscribe(channel)

    double_consumer = DoubleConsumer.new
    double_consumer.subscribe(channel)

    mixed_actor = MixedActor.new
    mixed_actor.subscribe(channel)

    it do
      channel.emit(TestEvent::A.new("foo"))
      Fiber.yield

      SimpleSubscriber.latest_value.should eq "foo"
      DoubleSubscriber.latest_value_a.should eq "foo"
      SimpleConsumer.latest_value.should eq "foo"
      DoubleConsumer.latest_value_a.should eq "foo"
      MixedActor.latest_value_a.should eq "foo"

      channel.emit(TestEvent::B.new(42))
      Fiber.yield

      DoubleSubscriber.latest_value_b.should eq 42
      DoubleConsumer.latest_value_b.should eq 42
      MixedActor.latest_value_b.should eq 42

      simple_subscriber.unsubscribe(channel)
      double_subscriber.unsubscribe(channel)
      simple_consumer.unsubscribe(channel)
      double_consumer.unsubscribe(channel)
      mixed_actor.unsubscribe(channel)
    end
  end
end
