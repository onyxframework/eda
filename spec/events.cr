abstract struct UserEvent
  include Onyx::EDA::Event

  getter id : Int32

  def initialize(@id : Int32)
  end
end

struct Users::Created < UserEvent
  def initialize(@id : Int32)
  end
end

struct Users::Deleted < UserEvent
  getter reason

  def initialize(@id : Int32, @reason : String)
  end
end

struct SomeOtherEvent
  include Onyx::EDA::Event

  getter foo

  def initialize(@foo : String)
  end
end
