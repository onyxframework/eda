require "uuid"
require "msgpack"

# Extensions to stdlib `UUID` struct.
struct UUID
  # Read from MessagePack input.
  def self.new(pull : MessagePack::Unpacker)
    new(Bytes.new(pull))
  end

  # Serialize into MessagePack bytes.
  def to_msgpack(packer : MessagePack::Packer)
    to_slice.to_msgpack(packer)
  end
end
