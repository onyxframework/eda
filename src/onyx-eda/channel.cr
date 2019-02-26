require "./event"

module Onyx::EDA
  # An in-memory event channel.
  # **Asynchronously** notifies all its subscribers on a new `Event`.
  #
  # ```
  # channel = Onyx::EDA::Channel.new
  # channel.subscribe(Object, MyEvent) { |e| pp e }
  # channel.emit(MyEvent.new)
  # sleep(0.01) # Need to yield the control, because all notifications are async
  # ```
  class Channel
    # Emit *events*, notifying all its subscribers.
    def emit(*events : *T) forall T
      emit(events)
    end

    # ditto
    def emit(events : Enumerable(T)) forall T
      events.each do |event|
        notify(event)
      end
    end

    # Subscribe an *object* to *event*, calling *proc* on event emit.
    #
    # Channel distinguishes subscribers by their `object.hash`.
    # You can have a single object subscribed to multiple events with multiple procs.
    # You can specify an abstract object, as well as a module in addition to
    # standard class and struct as *event*.
    #
    # Returns an array of the **newly** added event class names to watch,
    # skipping those which already have *at least one* subscriber.
    #
    # BUG: You currently can not pass a `Union` as an *event* argument.
    # Please subscribe multiple times with different events instead.
    #
    # ```
    # abstract struct AppEvent < Onyx::EDA::Event
    # end
    #
    # struct MyEvent < AppEvent
    #   getter foo
    #
    #   def initialize(@foo : String)
    #   end
    # end
    #
    # channel.subscribe(Object, AppEvent) do |event|
    #   pp event.foo
    # end # => ["MyEvent"]
    #
    # channel.subscribe(Object, MyEvent) do |event|
    #   pp event.foo
    # end # => []
    #
    # channel.emit(MyEvent.new("bar")) # Will print "bar" two times
    # ```
    #
    # You obviously can use it within objects as well:
    #
    # ```
    # class Notifier
    #   def initialize(channel)
    #     channel.subscribe(self, MyEvent) { }
    #   end
    #
    #   def stop
    #     channel.unsubscribe(self)
    #   end
    # end
    #
    # notifier = Notifier.new(channel)
    #
    # # ...
    #
    # channel.unsubscribe(notifier)
    # # Or
    # notifier.stop
    # ```
    def subscribe(object, event : T.class, &proc : T -> Nil) : Enumerable(String) forall T
      add_subscription(object, event, &proc)
    end

    # Unsubscribe an *object* from *event* notifications by *proc*.
    # The mentioned proc will not be called again for this subscriber.
    #
    # NOTE: You should pass exactly the same proc object.
    # `ProcNotSubscribedError` is raised otherwise.
    #
    # Returns an array of event class names which are not watched anymore,
    # i.e. those which have *zero* subscribers after this method call.
    #
    # ```
    # proc = ->(e : MyEvent) { pp e }
    #
    # channel.subscribe(Object, MyEvent, &proc)
    #
    # # Would raise ProcNotSubscribedError
    # channel.unsubscribe(Object, MyEvent) do |e|
    #   pp e
    # end
    #
    # # OK
    # channel.unsubscribe(Object, MyEvent, &proc) # => ["MyEvent"]
    # ```
    def unsubscribe(object, event : T.class, &proc : T -> Nil) : Enumerable(String) forall T
      remove_subscription(object, event, &proc)
    end

    # Unsubscribe an *object* from all *event* notifications.
    #
    # Returns an array of event class names which are not watched anymore,
    # i.e. those which have *zero* subscribers after this method call.
    #
    # ```
    # channel.subscribe(Object, MyEvent) do |event|
    #   pp event
    # end
    #
    # channel.unsubscribe(Object, MyEvent) # => ["MyEvent"]
    # ```
    def unsubscribe(object, event : T.class) : Enumerable(String) forall T
      remove_subscription(object, event)
    end

    # Unsubscribe an *object* from all events.
    #
    # Returns an array of event class names which are not watched anymore,
    # i.e. those which have *zero* subscribers after this method call.
    #
    # ```
    # channel.subscribe(Object, MyEvent) do |event|
    #   pp event
    # end
    #
    # channel.unsubscribe(Object) # => ["MyEvent"]
    # ```
    def unsubscribe(object) : Enumerable(String)
      remove_subscription(object)
    end

    @subscriptions : Hash(String, Hash(UInt64, Set(Tuple(String, Void*, Void*)))) = Hash(String, Hash(UInt64, Set(Tuple(String, Void*, Void*)))).new

    protected def add_subscription(object, event : T.class, &proc : T -> Nil) : Enumerable(String) forall T
      {%
        descendants = Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) }
        raise "#{T} has no descendants" if descendants.empty?
      %}

      tuple = { {{T.stringify}}, proc.pointer, proc.closure_data }
      object_hash = object.hash

      event_keys_added = Array(String).new

      {% for object in Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) && !t.abstract? } %}
        unless hash = @subscriptions[{{object.stringify}}]?
          hash = Hash(UInt64, Set(Tuple(String, Void*, Void*))).new
          @subscriptions[{{object.stringify}}] = hash
          event_keys_added << {{object.stringify}}
        end

        unless set = hash[object_hash]?
          set = Set(Tuple(String, Void*, Void*)).new
          hash[object_hash] = set
        end

        unless set.includes?(tuple)
          set << tuple
        end
      {% end %}

      return event_keys_added
    end

    protected def remove_subscription(object, event : T.class, &proc : T -> Nil) : Enumerable(String) forall T
      {%
        descendants = Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) }
        raise "#{T} has no descendants" if descendants.empty?
      %}

      tuple = { {{T.stringify}}, proc.pointer, proc.closure_data }
      object_hash = object.hash

      anything_removed = false
      event_keys_removed = Array(String).new

      {% for object in Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) && !t.abstract? } %}
        if hash = @subscriptions[{{object.stringify}}]?
          if proc_set = hash[object_hash]?
            if proc_set.includes?(tuple)
              proc_set.delete(tuple)
              anything_removed = true

              if proc_set.empty?
                hash[object_hash].delete(proc_set)

                if hash.empty?
                  @subscriptions.delete({{object.stringify}})
                  event_keys_removed << {{object.stringify}}
                end
              end
            end
          end
        end
      {% end %}

      raise ProcNotSubscribedError.new(proc) unless anything_removed
      return event_keys_removed
    end

    protected def remove_subscription(object, event : T.class) : Enumerable(String) forall T
      {%
        descendants = Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) }
        raise "#{T} has no descendants" if descendants.empty?
      %}

      object_hash = object.hash
      event_keys_removed = Array(String).new

      {% for object in Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) && !t.abstract? } %}
        if hash = @subscriptions[{{object.stringify}}]?
          removed = hash.delete(object_hash)

          if hash.empty?
            @subscriptions.delete({{object.stringify}})
            event_keys_removed << {{object.stringify}}
          end
        end
      {% end %}

      return event_keys_removed
    end

    protected def remove_subscription(object) : Enumerable(String)
      object_hash = object.hash

      event_keys_removed = Array(String).new

      @subscriptions.each do |event, hash|
        removed = hash.delete(object_hash)

        if hash.empty?
          @subscriptions.delete(event)
          event_keys_removed << event
        end
      end

      return event_keys_removed
    end

    protected def notify(event : T) : Nil forall T
      {%
        descendants = Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) && !t.abstract? }
        raise "#{T} has no descendants" if descendants.empty?
      %}

      {% for object in Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) } %}
        @subscriptions[{{object.stringify}}]?.try do |hash|
          hash.each do |_, proc_set|
            proc_set.each do |(type, pointer, closure_data)|
              {% begin %}
                case type
                {% for type in (Class.all_subclasses.select { |t| t.instance >= T && !(t.instance <= Object) }.map(&.instance) + Object.all_subclasses.select { |t| t >= T && (t < Reference || t < Struct) }).uniq %}
                  when {{type.stringify}}
                    spawn Proc({{type}}, Nil).new(pointer, closure_data).call(event.as({{type}}))
                {% end %}
                else
                  raise "BUG: Unmatched event type #{type}"
                end
              {% end %}
            end
          end
        end
      {% end %}
    end

    # Raised if attempted to call [`Channel#unsubscribe(object, event, &proc`)](../Channel.html#unsubscribe%28object%2Cevent%3AT.class%2C%26proc%3AT-%3ENil%29%3AEnumerable%28String%29forallT-instance-method)
    # with a *proc*, which is not currently in the list of subscribers.
    #
    # Typical mistake:
    #
    # ```
    # channel.subscribe(Object, MyEvent) do |event|
    #   pp event
    # end
    #
    # channel.unsubscribe(Object, MyEvent) do |event|
    #   pp event
    # end
    # ```
    #
    # The code above would raise, because these blocks result in two different procs.
    # Valid approach:
    #
    # ```
    # proc = ->(event : MyEvent) { pp event }
    # channel.subscribe(Object, MyEvent, &proc)
    # channel.unsubscribe(Object, MyEvent, &proc)
    # ```
    class ProcNotSubscribedError < Exception
      def initialize(proc)
        super("Proc #{proc} is not in the list of subscriptions. Make sure you're referencing the exact same proc")
      end
    end
  end
end
