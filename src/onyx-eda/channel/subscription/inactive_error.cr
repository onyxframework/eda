abstract class Onyx::EDA::Channel
  class Subscription(T)
    # Raised on `Subscription#unsubscribe` method call if the instance is not
    # currently active (i.e. already cancelled).
    class InactiveError < Exception
      # :nodoc:
      protected def initialize
        super("This subscription is not active")
      end
    end
  end
end
