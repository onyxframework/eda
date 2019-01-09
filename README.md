<a href="https://onyxframework.org"><img align="right" width="147" height="147" src="https://onyxframework.org/img/logo.svg"></a>

# Onyx::Event

[![Built with Crystal](https://img.shields.io/badge/built%20with-crystal-000000.svg?style=flat-square)](https://crystal-lang.org/)
[![Travis CI build](https://img.shields.io/travis/onyxframework/event/master.svg?style=flat-square)](https://travis-ci.org/onyxframework/event)
[![Docs](https://img.shields.io/badge/docs-online-brightgreen.svg?style=flat-square)](https://docs.onyxframework.org/event)
[![API docs](https://img.shields.io/badge/api_docs-online-brightgreen.svg?style=flat-square)](https://api.onyxframework.org/event)
[![Latest release](https://img.shields.io/github/release/onyxframework/event.svg?style=flat-square)](https://github.com/onyxframework/event/releases)

An [Event-Driven Architecture](https://en.wikipedia.org/wiki/Event-driven_architecture) framework for [Crystal](https://crystal-lang.org).

## About

`Onyx::Event` brings the [Event-Driven Architecture](https://en.wikipedia.org/wiki/Event-driven_architecture) to the [Crystal Language](https://crystal-lang.org), making it possible to build event-driven applications fast. It allows to emit events and attach subscribers (and also consumers) to these events, via multiple channels.

### Features comparison

Onyx Framework is an [open-core software](https://en.wikipedia.org/wiki/Open-core_model), which ensures its long-term support and development. Purchasing a commercial license gives you a Github team membership with an access to private repositories containing extra features and also an access to private [Twist](https://twist.com) team for extened support. Read more at [Commercial FAQ](https://docs.onyxframework.com/faq).

Feature | Open Source (this repo) | Pro | Enterprise
--- | :---: | :---: | :---:
[Subscribers](https://docs.onyxframework.org/event/subscriptions) | ✔ | ✔ | ✔
[Memory channel](https://docs.onyxframework.org/event/channel/memory) | ✔ | ✔ | ✔
[Redis channel](https://docs.onyxframework.org/event/channel/redis) | ✔ | ✔ | ✔
[Consumers](https://docs.onyxframework.com/event/consumers) | ✘ | ✔ | ✔
[Redis store](https://docs.onyxframework.com/event/store/redis) | ✘ | ✔ | ✔
[DB store](https://docs.onyxframework.com/event/store/db) | ✘ | ✔ | ✔
[Kafka channel](https://docs.onyxframework.com/event/channel/kafka) | ✘ | ✘ | ✔
[RabbitMQ channel](https://docs.onyxframework.com/event/channel/rabbitmq) | ✘ | ✘ | ✔
[On-demand custom channels](https://docs.onyxframework.com/event/channel/custom) | ✘ | ✘ | ✔
[On-demand custom stores](https://docs.onyxframework.org/event/store/custom) | ✘ | ✘ | ✔
**License** | [BSD 3-Clause](LICENSE) | [Commercial](https://docs.onyxframework.com/licensing/pro) | [Custom](https://docs.onyxframework.com/licensing/enterprise)
**Price** | Free | ~~$100~~ $50/month\* | [Contact us](mailto:enterprise@onyxframework.com)

*\* A 50% discount is applicable until version 1.0 of this software.*

## Installation

Add this to your application's `shard.yml`:

```diff
dependencies:
+   onyx-event:
+     github: onyxframework/event
+     version: ~> 0.0.1
```

This shard follows [Semantic Versioning v2.0.0](http://semver.org/), so check [releases](https://github.com/onyxframework/event/releases) and change the `version` accordingly. Please visit [github.com/crystal-lang/shards](https://github.com/crystal-lang/shards) to know more about Crystal shards.

## Usage

### Documentation

For a deeper information on usage, please visit:

* [docs.onyxframework.org/event](https://docs.onyxframework.org/event) — handcrafted documentation and guides
* [api.onyxframework.org/event](https://api.onyxframework.org/event) — auto-generated API documentation

### Example

First of all, define some events for your application:

```crystal
require "onyx-event"

struct MyEvent < Onyx::Event
  getter foo

  def initialize(@foo : String)
  end
end
```

<p align="right"><sup><code>event.cr</code></sup></p>

Then define an event generator:

```crystal
require "onyx-event/channel/redis"
require "./event"

channel = Onyx::Event::Channel::Redis.new

loop do
  sleep(1)
  channel.send(MyEvent.new(Time.now.to_s))
  puts "Sent MyEvent"
end
```

<p align="right"><sup><code>generator.cr</code></sup></p>

And a consumer:

```crystal
require "onyx-event/channel/redis"
require "./event"

channel = Onyx::Event::Channel::Redis.new

channel.subscribe(MyEvent) do |event|
  puts "Got #{typeof(event)}: #{event.foo}"
end

sleep
```

<p align="right"><sup><code>consumer.cr</code></sup></p>

Then launch the generator and arbitrary amount of consumers:

```console
$ crystal generator.cr
Sent MyEvent
Sent MyEvent
```

```console
$ crystal consumer.cr
Got MyEvent: 2019-01-09 17:20:10 +03:00
Got MyEvent: 2019-01-09 17:20:11 +03:00
```

## Contributing

1. Fork it (https://github.com/onyxframework/rest/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'feat: new feature'`) using [angular-style commits](https://docs.onyxframework.org/contributing/commit-style)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Licensing

This software is licensed under [BSD 3-Clause License](LICENSE).

[![Open Source Initiative](https://upload.wikimedia.org/wikipedia/commons/thumb/4/42/Opensource.svg/100px-Opensource.svg.png)](https://opensource.org/licenses/BSD-3-Clause)
