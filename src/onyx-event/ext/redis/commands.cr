# Extensions to the original [Redis Client](https://github.com/stefanwille/crystal-redis),
# which is authored by [Stefan Wille](https://github.com/stefanwille).
class Redis
  # Extensions to the original [Redis Client](https://github.com/stefanwille/crystal-redis) commands.
  module Commands
    # Return the client ID for the current connection.
    # See [https://redis.io/commands/client-id](https://redis.io/commands/client-id).
    def client_id
      integer_command(["CLIENT", "ID"])
    end

    # Set the current connection name.
    # See [https://redis.io/commands/client-setname](https://redis.io/commands/client-setname).
    def client_setname(name : String)
      string_command(["CLIENT", "SETNAME", name]) == "OK"
    end

    # Unblock a client blocked in a blocking command from a different connection.
    # See [https://redis.io/commands/client-unblock](https://redis.io/commands/client-unblock).
    def client_unblock(id : Int, error error? : Bool = false)
      commands = ["CLIENT", "UNBLOCK", id.to_s]

      if error = error?
        commands << "ERROR"
      end

      integer_command(commands)
    end

    # Appends a new entry to a stream.
    # See [https://redis.io/commands/xadd](https://redis.io/commands/xadd).
    def xadd(key : String, id : String | Char, *values : String)
      string_command(["XADD", key, id.to_s] + values.to_a)
    end

    # Return never seen elements in multiple streams,
    # with IDs greater than the ones reported by the caller for each stream. Can block.
    # See [https://redis.io/commands/xread](https://redis.io/commands/xread).
    def xread(streams : Enumerable(String), id : Enumerable(String), count : Int? = nil, block : Int? = nil)
      commands = ["XREAD"]

      commands += ["COUNT", count.to_s] if count
      commands += ["BLOCK", block.to_s] if block

      commands << "STREAMS"
      commands += streams.to_a
      commands += id.to_a

      array_or_nil_command(commands)
    end
  end
end
