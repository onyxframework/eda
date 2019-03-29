require "../../spec_helper"

class Onyx::EDA::Channel::Memory
  struct TestEvent::A
    include Onyx::EDA::Event

    getter payload : String

    def initialize(@payload : String)
    end
  end

  struct TestEvent::B
    include Onyx::EDA::Event

    getter payload : Int32

    def initialize(@payload : Int32)
    end
  end

  describe self do
    channel = self.new
    buffer = Hash(String, String | Int32).new

    describe "subscription" do
      it do
        sub_a = channel.subscribe(TestEvent::A) do |event|
          buffer["a"] = event.payload
        end

        sub_b = channel.subscribe(TestEvent::B) do |event|
          buffer["b"] = event.payload
        end

        sub_c = channel.subscribe(TestEvent::B, payload: 42) do |event|
          buffer["c"] = event.payload
        end

        channel.emit(TestEvent::A.new("foo"), TestEvent::B.new(42))
        Fiber.yield

        buffer["a"].should eq "foo"
        buffer["b"].should eq 42
        buffer["c"].should eq 42

        buffer.clear

        channel.emit(TestEvent::B.new(43))
        Fiber.yield

        buffer["a"]?.should be_nil # A is not emitted
        buffer["b"].should eq 43
        buffer["c"]?.should be_nil # C doesn't match the filter

        buffer.clear

        sub_a.unsubscribe.should be_true
        channel.unsubscribe(sub_b).should be_true
        sub_c.unsubscribe.should be_true
      end
    end

    describe "consumption" do
      it do
        sub_a = channel.subscribe(TestEvent::A, "foo") do |event|
          buffer["a"] = event.payload
        end

        sub_b = channel.subscribe(TestEvent::B, "foo") do |event|
          buffer["b"] = event.payload
        end

        sub_c = channel.subscribe(TestEvent::B, "bar") do |event|
          buffer["c"] = event.payload
        end

        channel.emit(TestEvent::A.new("foo"), TestEvent::B.new(42))
        Fiber.yield

        buffer["a"].should eq "foo"
        buffer["b"].should eq 42
        buffer["c"].should eq 42

        buffer.clear

        sub_a.unsubscribe.should be_true
        channel.unsubscribe(sub_b).should be_true
        sub_c.unsubscribe.should be_true
      end
    end

    describe "awaiting" do
      spawn do
        buffer["a"] = channel.await(TestEvent::A).payload
      end

      spawn do
        select
        when event = channel.await(TestEvent::A, payload: "bar")
          buffer["b"] = event.payload
        end
      end

      spawn do
        buffer["c"] = channel.await(TestEvent::B, &.payload)
      end

      Fiber.yield

      it do
        channel.emit([TestEvent::A.new("foo")])
        channel.emit([TestEvent::B.new(42)])
        Fiber.yield

        buffer["a"].should eq "foo"
        buffer["b"]?.should be_nil # Because it has filter
        buffer["c"].should eq 42

        buffer.clear
      end
    end
  end
end
