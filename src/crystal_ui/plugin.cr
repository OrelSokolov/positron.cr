require "json"

module CrystalUI
  # Base class for all CrystalUI plugins.
  #
  # Plugins live inside the Crystal Host. They request native services
  # through the host and emit events via EventBus.
  abstract class Plugin
    # Unique plugin identifier, e.g. "camera".
    abstract def name : String

    # Platforms supported by this plugin, e.g. [:desktop, :android, :ios].
    abstract def supported_platforms : Array(Symbol)

    # Called by the host when an OS event is routed to this plugin.
    def on_event(event : String, payload : JSON::Any)
      # override in subclass
    end

    # Called once during application startup.
    def on_ready(host : DesktopHost)
      # override in subclass
    end

    # Returns true if the plugin supports the current platform.
    def supports?(platform : Symbol) : Bool
      supported_platforms.includes?(platform)
    end
  end

  # Simple plugin registry.
  class PluginManager
    @plugins = Hash(String, Plugin).new

    def register(plugin : Plugin)
      @plugins[plugin.name] = plugin
    end

    def [](name : String) : Plugin
      @plugins[name]
    end

    def []?(name : String) : Plugin?
      @plugins[name]?
    end

    def each(&block : Plugin ->)
      @plugins.each_value(&block)
    end
  end
end
