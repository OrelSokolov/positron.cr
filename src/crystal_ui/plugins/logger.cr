require "json"
require "log"

module CrystalUI::Plugins
  # Cross-platform logging plugin.
  #
  # Exposes a single `logger.log` command that the frontend can use to send
  # log entries through the host's `Log` backend. This is a pure-host plugin:
  # it needs no native shim and works on every platform.
  class Logger < CrystalUI::Plugin
    def name : String
      "logger"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "logger.log" => CrystalUI::CommandManifest.new(
          name: "logger.log",
          args: [
            CrystalUI::ArgumentManifest.new(name: "level", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "message", type: "String"),
          ],
          returns: "Bool",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("logger.log") do |request|
        level = request.args["level"]?.try(&.as_s?) || "info"
        message = request.args["message"]?.try(&.as_s?) || ""

        log(level, message)

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(true.to_json)
        )
      end
    end

    private def log(level : String, message : String)
      logger = Log.for("crystalui.plugins.logger")
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
