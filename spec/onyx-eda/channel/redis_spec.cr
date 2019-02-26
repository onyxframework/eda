require "../../spec_helper"
require "../../../src/onyx-eda/channel/redis"
require "../../events"

describe Onyx::EDA::Channel::Redis do
  channel = Onyx::EDA::Channel::Redis.new(ENV["REDIS_URL"])

  invocations_hash = {
    UserEvent          => 0,
    "AnotherUserEvent" => 0,
    Users::Deleted     => 0,
    SomeOtherEvent     => 0,
    Onyx::EDA::Event   => 0,
  }

  user_event_proc = ->(event : UserEvent) {
    a, b = event.class, event.id
    invocations_hash[UserEvent] += 1
  }

  channel.subscribe(Object, UserEvent, &user_event_proc)

  channel.subscribe(Object, UserEvent) do |event|
    a, b = event.class, event.id
    invocations_hash["AnotherUserEvent"] += 1
  end

  channel.subscribe(Object, SomeOtherEvent) do |event|
    a, b = event.class, event.foo
    invocations_hash[SomeOtherEvent] += 1
  end

  channel.subscribe(Object, Users::Deleted) do |event|
    a, b, c = event.class, event.id, event.reason
    invocations_hash[Users::Deleted] += 1
  end

  channel.subscribe(Object, Onyx::EDA::Event) do |event|
    a = event.class
    invocations_hash[Onyx::EDA::Event] += 1
  end

  describe "#emit" do
    it do
      channel.emit(Users::Created.new(42)).should_not be_empty
    end
  end

  sleep(0.1)

  describe "emitting Users::Created event" do
    it "invokes UserEvent subscription" do
      invocations_hash[UserEvent].should eq 1
    end

    it "invokes AnotherUserEvent subscription" do
      invocations_hash["AnotherUserEvent"].should eq 1
    end

    it "does not invoke Users::Deleted subscription" do
      invocations_hash[Users::Deleted].should eq 0
    end

    it "does not invoke SomeOtherEvent subscription" do
      invocations_hash[SomeOtherEvent].should eq 0
    end

    it "invokes Onyx::EDA::Event subscription" do
      invocations_hash[Onyx::EDA::Event].should eq 1
    end
  end

  describe "#emit" do
    it do
      channel.emit(Users::Deleted.new(42, "migrated"), SomeOtherEvent.new("bar")).should_not be_empty
    end
  end

  sleep(0.1)

  describe "emitting Users::Deleted event" do
    it "does not invoke UserEvent subscription" do
      invocations_hash[UserEvent].should eq 2
    end

    it "does not invoke AnotherUserEvent subscription" do
      invocations_hash["AnotherUserEvent"].should eq 2
    end

    it "does not invoke Users::Deleted subscription" do
      invocations_hash[Users::Deleted].should eq 1
    end

    it "invokes SomeOtherEvent subscription" do
      invocations_hash[SomeOtherEvent].should eq 1
    end

    it "invokes Onyx::EDA::Event subscription" do
      invocations_hash[Onyx::EDA::Event].should eq 3
    end
  end
end
