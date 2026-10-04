require "json"
require "log"

module Positron
  # Represents a request coming from the UI surface (WebView) or a plugin.
  record CommandRequest,
    id : String,
    name : String,
    args : JSON::Any

  # Result of a command invocation.
  record CommandResult,
    success : Bool,
    data : JSON::Any,
    error : String? = nil

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
    def register(name : String, &block : CommandRequest -> CommandResult)
      @commands[name] = block
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
      parsed = JSON.parse(json)
      CommandRequest.new(
        id: parsed["id"].as_s? || "",
        name: parsed["name"].as_s? || "",
        args: parsed["args"]? || JSON.parse("{}")
      )
    end

    # Build a JavaScript call that resolves the WebView Promise.
    # Signature: window.__positronResolve(id, success, data, error)
    def self.to_js_resolve(request : CommandRequest, result : CommandResult) : String
      id = request.id.to_json
      success = result.success.to_json
      data = result.data.to_json
      error = result.error.nil? ? "null" : result.error.to_json

      "window.__positronResolve(#{id}, #{success}, #{data}, #{error})"
    end
  end

  # Annotation used to expose application methods as commands.
  annotation Command
  end
end
