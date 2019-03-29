abstract class Onyx::EDA::Channel
  # Raised on `Channel#subscribe` with *consumer_id* argument if a consumer with the
  # same ID already exists in this process for this channel.
  class DuplicateConsumerError(T) < Exception
    getter consumer_id : String

    def event : T.class
      T.class
    end

    protected def self.new(event : T.class, consumer_id : String) : DuplicateConsumerError(T) forall T
      DuplicateConsumerError(T).new(consumer_id)
    end

    # :nodoc:
    protected def initialize(@consumer_id : String)
      super("There can be only one `#{T}` consumer with ID #{@consumer_id.inspect} within a single channel instance")
    end
  end
end
