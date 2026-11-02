require "json"
require "log"

module Positron
  # Represents a request coming from the UI surface (WebView) or a plugin.
  record CommandRequest,
    id : String,
    name : String,
    args : JSON::Any

  # Result of a command invocation. `raw_json`, when set, is used
  # verbatim as the resolve payload (`to_js_resolve`) — the
  # single-serialization fast path for handlers that already produced
  # JSON, skipping `data.to_json`.
  record CommandResult,
    success : Bool,
    data : JSON::Any,
    error : String? = nil,
    raw_json : String? = nil

  # Metadata describing a command argument for JS facade generation.
  record ArgumentManifest,
    name : String,
    type : String

  # Metadata describing an exposed command for JS facade generation.
  record CommandManifest,
    name : String,
    args : Array(ArgumentManifest) = [] of ArgumentManifest,
    returns : String? = nil

  # Dispatches @[Command] annotated methods on application and plugin instances.
  # Commands may be namespaced, e.g. "settings.current_theme".
  class CommandRegistry
    @commands = Hash(String, Proc(CommandRequest, CommandResult)).new

    # Register a command by name.
    #
    # `execution` declares the character of the handler's work so the
    # framework picks the right context — apps never manage fibers:
    #
    #   :fiber    (default) — the handler runs in its dispatch fiber.
    #              Right for IO, subprocesses, anything that waits.
    #   :parallel             — the handler body runs on a
    #              Fiber::ExecutionContext::Parallel worker thread
    #              (Crystal >= 1.21). Right for CPU-bound loops, which
    #              would otherwise starve the cooperative scheduler and
    #              freeze the GUI. Such a handler must not touch the UI
    #              or GTK state — build a CommandResult and return it;
    #              handler exceptions become error results.
    def register(name : String, execution : Symbol = :fiber, &block : CommandRequest -> CommandResult)
      case execution
      when :parallel
        @commands[name] = ->(request : CommandRequest) do
          Positron.run_parallel do
            begin
              block.call(request)
            rescue ex
              CommandResult.new(
                success: false,
                data: JSON.parse("{}"),
                error: "parallel handler crashed: #{ex.message}"
              )
            end
          end
        end
      when :fiber
        @commands[name] = block
      else
        raise ArgumentError.new("unknown execution context #{execution.inspect} for command #{name} (use :fiber or :parallel)")
      end
    end

    # Dispatch a command request.
    def dispatch(request : CommandRequest) : CommandResult
      if handler = @commands[request.name]?
        handler.call(request)
      else
        CommandResult.new(
          success: false,
          data: JSON.parse("{}"),
          error: "Unknown command: #{request.name}"
        )
      end
    end

    # Helper to parse a raw JSON payload into a CommandRequest.
    def self.parse(json : String) : CommandRequest
      parse(JSON.parse(json))
    end

    # Same, without the string round-trip when the envelope is already
    # parsed (the async Host dispatch path).
    def self.parse(payload : JSON::Any) : CommandRequest
      CommandRequest.new(
        id: payload["id"]?.try(&.as_s?) || "",
        name: payload["name"]?.try(&.as_s?) || "",
        args: payload["args"]? || JSON.parse("{}")
      )
    end

    # Build a JavaScript call that resolves the WebView Promise.
    # Signature: window.__positronResolve(id, success, data, error)
    def self.to_js_resolve(request : CommandRequest, result : CommandResult) : String
      id = request.id.to_json
      success = result.success.to_json
      data = result.raw_json || result.data.to_json
      error = result.error.nil? ? "null" : result.error.to_json

      "window.__positronResolve(#{id}, #{success}, #{data}, #{error})"
    end
  end

  # Annotation used to expose application methods as commands.
  annotation Command
  end
end
