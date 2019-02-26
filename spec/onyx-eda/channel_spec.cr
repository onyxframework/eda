require "../spec_helper"
require "../events"

class NewUserNotifier
  def initialize(channel, invocations_hash)
    channel.subscribe(self, Users::Created) do |event|
      a, b = event.class, event.id
      invocations_hash[NewUserNotifier] += 1
    end
  end
end

describe Onyx::EDA::Channel do
  channel = Onyx::EDA::Channel.new

  invocations_hash = {
    UserEvent          => 0,
    "AnotherUserEvent" => 0,
    Users::Deleted     => 0,
    SomeOtherEvent     => 0,
    Onyx::EDA::Event   => 0,
    NewUserNotifier    => 0,
  }

  user_event_proc = ->(event : UserEvent) {
    a, b = event.class, event.id
    invocations_hash[UserEvent] += 1
  }

  notifier = uninitialized NewUserNotifier

  describe "#subscribe" do
    context "when new event" do
      it "returns array with added event names" do
        channel.subscribe(Object, UserEvent, &user_event_proc).should eq ["Users::Created", "Users::Deleted"]
      end

      it "returns array with added event names" do
        channel.subscribe(Object, SomeOtherEvent) do |event|
          a, b = event.class, event.foo
          invocations_hash[SomeOtherEvent] += 1
        end.should eq ["SomeOtherEvent"]
      end
    end

    notifier = NewUserNotifier.new(channel, invocations_hash)

    context "when existing event" do
      it "returns empty array" do
        channel.subscribe(Object, UserEvent) do |event|
          a, b = event.class, event.id
          invocations_hash["AnotherUserEvent"] += 1
        end.should be_empty
      end

      it "returns empty array" do
        channel.subscribe(Object, Users::Deleted) do |event|
          a, b, c = event.class, event.id, event.reason
          invocations_hash[Users::Deleted] += 1
        end.should be_empty
      end

      it "returns empty array" do
        channel.subscribe(Object, Onyx::EDA::Event) do |event|
          a = event.class
          invocations_hash[Onyx::EDA::Event] += 1
        end.should be_empty
      end
    end
  end

  describe "emitting Users::Created event" do
    spawn channel.emit(Users::Created.new(42))

    sleep(0.01)

    it "notifies UserEvent subscriber" do
      invocations_hash[UserEvent].should eq 1
    end

    it "notifies AnotherUserEvent subscriber" do
      invocations_hash["AnotherUserEvent"].should eq 1
    end

    it "does not notify Users::Deleted subscriber" do
      invocations_hash[Users::Deleted].should eq 0
    end

    it "does not notify SomeOtherEvent subscriber" do
      invocations_hash[SomeOtherEvent].should eq 0
    end

    it "notifies Onyx::EDA::Event subscriber" do
      invocations_hash[Onyx::EDA::Event].should eq 1
    end

    it "notifies NewUserNotifier" do
      invocations_hash[NewUserNotifier].should eq 1
    end
  end

  describe "emitting Users::Deleted event" do
    spawn channel.emit(Users::Deleted.new(43, "migrated"))

    sleep(0.01)

    it "notifies UserEvent subscriber" do
      invocations_hash[UserEvent].should eq 2
    end

    it "notifies AnotherUserEvent subscriber" do
      invocations_hash["AnotherUserEvent"].should eq 2
    end

    it "notifies Users::Deleted subscriber" do
      invocations_hash[Users::Deleted].should eq 1
    end

    it "does not notify SomeOtherEvent subscriber" do
      invocations_hash[SomeOtherEvent].should eq 0
    end

    it "notifies Onyx::EDA::Event subscriber" do
      invocations_hash[Onyx::EDA::Event].should eq 2
    end

    it "does not notify NewUserNotifier" do
      invocations_hash[NewUserNotifier].should eq 1
    end
  end

  describe "emitting SomeOtherEvent event" do
    spawn channel.emit(SomeOtherEvent.new("bar"))

    sleep(0.01)

    it "does not UserEvent subscriber" do
      invocations_hash[UserEvent].should eq 2
    end

    it "does not AnotherUserEvent subscriber" do
      invocations_hash["AnotherUserEvent"].should eq 2
    end

    it "does not Users::Deleted subscriber" do
      invocations_hash[Users::Deleted].should eq 1
    end

    it "notifies SomeOtherEvent subscriber" do
      invocations_hash[SomeOtherEvent].should eq 1
    end

    it "notifies Onyx::EDA::Event subscriber" do
      invocations_hash[Onyx::EDA::Event].should eq 3
    end

    it "does not notify NewUserNotifier" do
      invocations_hash[NewUserNotifier].should eq 1
    end
  end

  channel.unsubscribe(notifier)

  invocations_hash = {
    UserEvent          => 0,
    "AnotherUserEvent" => 0,
    Users::Deleted     => 0,
    SomeOtherEvent     => 0,
    Onyx::EDA::Event   => 0,
    NewUserNotifier    => 0,
  }

  notifier = NewUserNotifier.new(channel, invocations_hash)

  context "when unsubscribed Object by UserEvent by proc" do
    describe "#unsubscribe" do
      it "returns empty array" do
        channel.unsubscribe(Object, UserEvent, &user_event_proc).should be_empty
      end
    end

    describe "emitting Users::Created event" do
      spawn channel.emit(Users::Created.new(42))

      sleep(0.01)

      it "skips UserEvent subscriber" do
        invocations_hash[UserEvent].should eq 0
      end

      it "notifies AnotherUserEvent subscriber" do
        invocations_hash["AnotherUserEvent"].should eq 1
      end

      it "notifies Onyx::EDA::Event subscriber" do
        invocations_hash[Onyx::EDA::Event].should eq 1
      end

      it "notifies NewUserNotifier" do
        invocations_hash[NewUserNotifier].should eq 1
      end
    end
  end

  context "when unsubscribed Object by UserEvent" do
    describe "#unsubscribe" do
      it "returns array of removed event keys" do
        channel.unsubscribe(Object, UserEvent).should eq ["Users::Deleted"]
      end
    end

    describe "emitting Users::Created event" do
      spawn channel.emit(Users::Created.new(42), Users::Created.new(42))

      sleep(0.01)

      it "skips UserEvent subscriber" do
        invocations_hash[UserEvent].should eq 0
      end

      it "skips AnotherUserEvent subscriber" do
        invocations_hash["AnotherUserEvent"].should eq 1
      end

      it "skips Onyx::EDA::Event subscriber" do
        invocations_hash[Onyx::EDA::Event].should eq 1
      end

      it "notifies NewUserNotifier" do
        invocations_hash[NewUserNotifier].should eq 3
      end
    end
  end

  context "when unsubscribed Object" do
    describe "#unsubscribe" do
      it "returns array of removed event keys" do
        channel.unsubscribe(Object).should eq ["SomeOtherEvent"]
      end
    end

    describe "emitting SomeOtherEvent event" do
      spawn channel.emit(SomeOtherEvent.new("bar"))

      sleep(0.01)

      it "skips UserEvent subscriber" do
        invocations_hash[UserEvent].should eq 0
      end

      it "skips AnotherUserEvent subscriber" do
        invocations_hash["AnotherUserEvent"].should eq 1
      end

      it "skips SomeOtherEvent subscriber" do
        invocations_hash[SomeOtherEvent].should eq 0
      end

      it "skips Onyx::EDA::Event subscriber" do
        invocations_hash[Onyx::EDA::Event].should eq 1
      end

      it "does not notify NewUserNotifier" do
        invocations_hash[NewUserNotifier].should eq 3
      end
    end
  end

  context "when unsubscribed NewUserNotifier" do
    describe "#unsubscribe" do
      it "returns array of removed event keys" do
        channel.unsubscribe(notifier).should eq ["Users::Created"]
      end
    end

    describe "emitting Users::Created event" do
      spawn channel.emit(Users::Created.new(42))

      sleep(0.01)

      it "skips UserEvent subscriber" do
        invocations_hash[UserEvent].should eq 0
      end

      it "skips AnotherUserEvent subscriber" do
        invocations_hash["AnotherUserEvent"].should eq 1
      end

      it "skips SomeOtherEvent subscriber" do
        invocations_hash[SomeOtherEvent].should eq 0
      end

      it "skips Onyx::EDA::Event subscriber" do
        invocations_hash[Onyx::EDA::Event].should eq 1
      end

      it "skips NewUserNotifier" do
        invocations_hash[NewUserNotifier].should eq 3
      end
    end
  end
end
