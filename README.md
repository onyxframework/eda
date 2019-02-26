<a href="https://onyxframework.org"><img width="100" height="100" src="https://onyxframework.org/img/logo.svg"></a>

# Onyx::EDA

[![Built with Crystal](https://img.shields.io/badge/built%20with-crystal-000000.svg?style=flat-square)](https://crystal-lang.org/)
[![Travis CI build](https://img.shields.io/travis/onyxframework/eda/master.svg?style=flat-square)](https://travis-ci.org/onyxframework/eda)
[![API docs](https://img.shields.io/badge/api_docs-online-brightgreen.svg?style=flat-square)](https://api.onyxframework.org/eda)
[![Latest release](https://img.shields.io/github/release/onyxframework/eda.svg?style=flat-square)](https://github.com/onyxframework/eda/releases)

An Event-Driven Architecture framework to build reactive apps.

## Supporters ❤️

Thanks to all my patrons, I can continue working on beautiful Open Source Software! 🙏

[Lauri Jutila](https://github.com/ljuti), [Alexander Maslov](https://seendex.ru), Dainel Vera

*You can become a patron too in exchange of prioritized support and other perks*

<a href="https://www.patreon.com/vladfaust"><img height="50" src="https://onyxframework.org/img/patreon-button.svg"></a>

## About 👋

Onyx::EDA is an [Event-Driven Architecture](https://en.wikipedia.org/wiki/Event-driven_architecture) framework. It allows to emit certain *events* and subscribe to them.

It has several *channels* implemented:

* [In-memory channel](https://api.onyxframework.org/eda/Onyx/EDA/Channel.html)
* [Redis channel](https://api.onyxframework.org/eda/Onyx/EDA/Channel/Redis.html) (working on [Redis streams](https://redis.io/topics/streams-intro))

## Installation 📥

Add this to your application's `shard.yml`:

```yaml
dependencies:
  onyx-eda:
    github: onyxframework/eda
    version: ~> 0.2.0
```

This shard follows [Semantic Versioning v2.0.0](http://semver.org/), so check [releases](https://github.com/onyxframework/rest/releases) and change the `version` accordingly. Please visit [github.com/crystal-lang/shards](https://github.com/crystal-lang/shards) to know more about Crystal shards.

## Usage 💻

First of all, you need to create a channel:

```crystal
require "onyx-eda"
channel = Onyx::EDA::Channel.new

# or
#

require "onyx-eda"
require "onyx-eda/channel/redis"

channel = Onyx::EDA::Channel::Redis.new("redis://localhost:6379")
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

Subscribe an object to the event:

```crystal
# Top-level subscription
channel.subscribe(Object, MyEvent) do |event|
  pp event.foo
end

# Object-level subscriptions
#

class Notifier
  def initialize(channel)
    channel.subscribe(self, MyEvent) do |event|
      pp event.foo
    end
  end
end

notifier = Notifier.new(channel)
```

Then emit the event:

```crystal
channel.emit(MyEvent.new("bar"))
```

All subscribers will asynchronously notified of the new event. You can then unsubscribe:

```crystal
channel.unsubscribe(notifier)
```

### Using with Onyx top-level macros

[Onyx](https://github.com/onyxframework/onyx) shard has convenient macros to reduce boilerplate code. Once [`"onyx/eda"`](https://github.com/onyxframework/onyx#eda) is required, a singleton `Onyx.channel` is defined. You can then specify which channel to use, for example, `Onyx.channel(:redis)`.

```crystal
require "onyx/eda"

struct MyEvent
  # ditto
end

Onyx.channel(:redis)

Onyx.subscribe(Object, MyEvent) do |event|
  # ditto
end

Onyx.emit(MyEvent.new("bar"))
# or
Onyx.channel.emit(MyEvent.new("bar"))

sleep(0.1)

Onyx.unsubscibe(Object)
```

## Community 🍪

There are multiple places to talk about this particular shard and about other ones as well:

* [Onyx::EDA Gitter chat](https://gitter.im/onyxframework/eda)
* [Onyx Framework Gitter community](https://gitter.im/onyxframework)
* [Vlad Faust Gitter community](https://gitter.im/vladfaust)
* [Onyx Framework Twitter](https://twitter.com/onyxframework)
* [Onyx Framework Telegram channel](https://telegram.me/onyxframework)

## Support ❤️

This shard is maintained by me, [Vlad Faust](https://vladfaust.com), a passionate developer with years of programming and product experience. I love creating Open-Source and I want to be able to work full-time on Open-Source projects.

I will do my best to answer your questions in the free communication channels above, but if you want prioritized support, then please consider becoming my patron. Your issues will be labeled with your patronage status, and if you have a sponsor tier, then you and your team be able to communicate with me in private or semi-private channels such as e-mail and [Twist](https://twist.com). There are other perks to consider, so please, don't hesistate to check my Patreon page:

<a href="https://www.patreon.com/vladfaust"><img height="50" src="https://onyxframework.org/img/patreon-button.svg"></a>

You could also help me a lot if you leave a star to this GitHub repository and spread the world about Crystal and Onyx! 📣

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
