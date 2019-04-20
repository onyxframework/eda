require "../../spec_helper"
require "../../../src/onyx-eda/channel/redis"

class Onyx::EDA::Channel::Redis
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
    channel = self.new(ENV["REDIS_URL"], logger: Logger.new(STDOUT))
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

        sleep(0.25)
        channel.emit(TestEvent::A.new("foo"), TestEvent::B.new(42))
        sleep(0.25)

        buffer["a"].should eq "foo"
        buffer["b"].should eq 42
        buffer["c"].should eq 42

        buffer.clear

        channel.emit(TestEvent::B.new(43))
        sleep(0.25)

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

        sleep(0.1)
        channel.emit(TestEvent::A.new("foo"), TestEvent::B.new(42))
        sleep(0.1)

        buffer["a"].should eq "foo"
        buffer["b"].should eq 42
        buffer["c"].should eq 42

        buffer.clear

        sub_a.unsubscribe.should be_true
        channel.unsubscribe(sub_b).should be_true
        sub_c.unsubscribe.should be_true
      end
    end
  end
end
