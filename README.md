<a href="https://onyxframework.org"><img width="100" height="100" src="https://onyxframework.org/img/logo.svg"></a>

# Onyx::EDA

[![Built with Crystal](https://img.shields.io/badge/built%20with-crystal-000000.svg?style=flat-square)](https://crystal-lang.org/)
[![Travis CI build](https://img.shields.io/travis/onyxframework/eda/master.svg?style=flat-square)](https://travis-ci.org/onyxframework/eda)
[![Docs](https://img.shields.io/badge/docs-online-brightgreen.svg?style=flat-square)](https://docs.onyxframework.org/eda)
[![API docs](https://img.shields.io/badge/api_docs-online-brightgreen.svg?style=flat-square)](https://api.onyxframework.org/eda)
[![Latest release](https://img.shields.io/github/release/onyxframework/eda.svg?style=flat-square)](https://github.com/onyxframework/eda/releases)

An Event-Driven Architecture framework to build reactive apps.

## About 👋

Onyx::EDA is an [Event-Driven Architecture](https://en.wikipedia.org/wiki/Event-driven_architecture) framework. It allows to emit certain *events* and subscribe to them.

Currently the framework has these *channels* implemented:

* [Memory channel](https://api.onyxframework.org/eda/Onyx/EDA/Channel/Memory.html)
* [Redis channel](https://api.onyxframework.org/eda/Onyx/EDA/Channel/Redis.html) (working on [Redis streams](https://redis.io/topics/streams-intro))

Onyx::EDA is a **real-time** events framework. It does not process events happend in the past and currently does not care about reliability in case of third-party service dependant channels (i.e. Redis).

👍 The framework is a great choice for reactive and/or distributed applications, effectively allowing to have multiple loosely-coupled components which do not directly interact with each other, but rely on events instead.

👎 However, Onyx::EDA is not a good choice for tasks requiring reliability, for example, background processing. If a Redis consumer dies during processing, the event is likely to not be processed. This behaviour may change in the future.

## Installation 📥

Add this to your application's `shard.yml`:

```yaml
dependencies:
  onyx:
    github: onyxframework/onyx
    version: ~> 0.4.0
  onyx-eda:
    github: onyxframework/eda
    version: ~> 0.3.0
```

This shard follows [Semantic Versioning v2.0.0](http://semver.org/), so check [releases](https://github.com/vladfaust/timer.cr/releases) and change the `version` accordingly.

> Note that until Crystal is officially released, this shard would be in beta state (`0.*.*`), with every **minor** release considered breaking. For example, `0.1.0` → `0.2.0` is breaking and `0.1.0` → `0.1.1` is not.

## Usage 💻

First of all, you must require channels you'd need:

```crystal
require "onyx/eda/memory"
require "onyx/eda/redis"
```

Then define events to emit:

```crystal
struct MyEvent
  include Onyx::EDA::Event

  getter foo

  def initialize(@foo : String)
  end
end
```

### Basic subscribing

You must define a block which would be run on incoming event:

```crystal
Onyx::EDA.memory.subscribe(MyEvent) do |event|
  pp event.foo
end
```

Subscribing and emitting are **asynchronous** operations. You must then `yield` the control with `sleep` or `Fiber.yield` to let notifications reach their subscriptions:

```crystal
Onyx::EDA.memory.emit(MyEvent.new("bar"))
sleep(1)
```

Output, as expected:

```
bar
```

You can cancel a subscription as well:

```crystal
sub = Onyx::EDA.memory.subscribe(MyEvent) do |event|
  pp event.foo
end

sub.unsubscribe
```

### Subscribing with filters

You can filter incoming events and run the subscription block only if the event's getters match the filter:

```crystal
# Would only put "bar"
Onyx::EDA.memory.subscribe(MyEvent, foo: "bar") do |event|
  pp event.foo
end

Onyx::EDA.memory.emit(MyEvent.new("qux")) # Would not notify the subscription above
Onyx::EDA.memory.emit(MyEvent.new("bar")) # OK, condition is met
```

### Consuming

You can create an event consumption instead of a subscription. From docs:

> Consumption differs from subscription in a way that only a single consuming subscription instance with certain *consumer_id* among all this channel subscribers would be notified about an event after it successfully acquires a lock. The lock implementation differs in channels.

In this code only **one** `"bar"` will be put, because both subscriptions have `"MyConsumer"` as the consumer ID:

```crystal
sub1 = Onyx::EDA.memory.subscribe(MyEvent, "MyConsumer") do |event|
  puts event.foo
end

sub2 = Onyx::EDA.memory.subscribe(MyEvent, "MyConsumer") do |event|
  puts event.foo
end

Onyx::EDA.memory.emit(MyEvent.new("bar"))
```

The consuming works as expected with [Redis channel](https://api.onyxframework.org/eda/Onyx/EDA/Channel/Redis.html) as well. It relies on [Redis streams](https://redis.io/topics/streams-intro). However, if a consumer crashes, then no other consumer with the same ID would try to process this event anymore (i.e. the behavior is unreliable). This may change in the future.

Note that you can not use event filters while consuming.

### Awaiting

It is possible to await for a certain event to happen in a **blocking** manner:

```crystal
# Will block the execution until the event is received
Onyx::EDA.memory.await(MyEvent) do |event|
  pp event.foo
end
```

It is particularly useful in `select` blocks:

```crystal
select
when event = Onyx::EDA.memory.await(MyEvent)
  pp event.foo
when Timer.new(30.seconds)
  raise "Timeout!"
end
```

*💡 See [timer.cr](https://github.com/vladfaust/timer.cr) for a timer shard.*

You can use filters with awaiting, making it possible to wait for a specific event hapenning:

```crystal
record MyEventHandled, parent_event_id : UUID do
  include Onyx::EDA::Event
end

event = Onyx::EDA.redis.emit(MyEvent.new("bar"))

select
when event = Onyx::EDA.redis.await(MyEventHandled, parent_event_id: event.event_id)
  puts "Handled"
when Timer.new(30.seconds)
  raise "Timeout!"
end
```

### `Subscriber` and `Consumer`

You can include the `Subscriber(T)` and `Consumer(T)` modules into an object, turning it into an event (`T`) subscriber or consumer. It must implement `handle(event : T)` and be explicitly subscribed to a channel.

```crystal
class Actor::Logger
  include Onyx::EDA::Subscriber(Event::User::Registered)
  include Onyx::EDA::Consumer(Event::Payment::Successfull)

  # This method will be called in *all* Actor::Logger instances
  def handle(event : Event::User::Registered)
    log_into_terminal("New user with id #{event.id}")
  end

  # This method will be called in only *one* Actor::Logger instance
  def handle(event : Event::Payment::Successfull)
    send_email("admin@example.com", "New payment of $#{event.amount}")
  end
end

actor = Actor::Logger.new
actor.subscribe(Onyx::EDA.memory)   # Non-blocking method
actor.unsubscribe(Onyx::EDA.memory) # Can be unsubscribed as well
```

## Documentation 📚

The documentation is available online at [docs.onyxframework.org/eda](https://docs.onyxframework.org/eda).

## Community 🍪

There are multiple places to talk about Onyx:

* [Gitter](https://gitter.im/onyxframework)
* [Twitter](https://twitter.com/onyxframework)

## Support 🕊

This shard is maintained by me, [Vlad Faust](https://vladfaust.com), a passionate developer with years of programming and product experience. I love creating Open-Source and I want to be able to work full-time on Open-Source projects.

I will do my best to answer your questions in the free communication channels above, but if you want prioritized support, then please consider becoming my patron. Your issues will be labeled with your patronage status, and if you have a sponsor tier, then you and your team be able to communicate with me privately in [Twist](https://twist.com). There are other perks to consider, so please, don't hesistate to check my Patreon page:

<a href="https://www.patreon.com/vladfaust"><img height="50" src="https://onyxframework.org/img/patreon-button.svg"></a>

You could also help me a lot if you leave a star to this GitHub repository and spread the word about Crystal and Onyx! 📣

## Contributing

1. Fork it ( https://github.com/onyxframework/eda/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'feat: some feature') using [Angular style commits](https://github.com/angular/angular/blob/master/CONTRIBUTING.md#commit)
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [Vlad Faust](https://github.com/vladfaust) - creator and maintainer

## Licensing

This software is licensed under [MIT License](LICENSE).

[![Open Source Initiative](https://upload.wikimedia.org/wikipedia/commons/thumb/4/42/Opensource.svg/100px-Opensource.svg.png)](https://opensource.org/licenses/MIT)
