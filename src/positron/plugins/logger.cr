require "json"
require "log"

module Positron::Plugins
  # Cross-platform logging plugin.
  #
  # Exposes a single `logger.log` command that the frontend can use to send
  # log entries through the host's `Log` backend. This is a pure-host plugin:
  # it needs no native shim and works on every platform.
  class Logger < Positron::Plugin
    def name : String
      "logger"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "logger.log" => Positron::CommandManifest.new(
          name: "logger.log",
          args: [
            Positron::ArgumentManifest.new(name: "level", type: "String"),
            Positron::ArgumentManifest.new(name: "message", type: "String"),
          ],
          returns: "Bool",
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("logger.log") do |request|
        level = request.args["level"]?.try(&.as_s?) || "info"
        message = request.args["message"]?.try(&.as_s?) || ""

        log(level, message)

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(true.to_json)
        )
      end
    end

    private def log(level : String, message : String)
      logger = Log.for("positron.plugins.logger")
      case level
      when "debug" then logger.debug { message }
      when "info"  then logger.info { message }
      when "warn"  then logger.warn { message }
      when "error" then logger.error { message }
      else
        logger.info { message }
      end
    end
  end
end
