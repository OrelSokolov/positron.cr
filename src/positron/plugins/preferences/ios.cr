require "json"
require "log"
require "./adapter"
require "../../adapters/ios/objc"

module Positron::Plugins
  # iOS implementation of persistent preferences.
  #
  # The whole preference map round-trips as a single JSON string
  # through NSUserDefaults (the standard defaults live in the app
  # container and survive relaunches); the in-memory hash stays the
  # source of truth for reads, like the file-backed macOS adapter.
  class IOSPreferencesAdapter < PreferencesAdapter
    ObjC = Positron::Adapters::IOS::ObjC

    @data = {} of String => JSON::Any
    @mutex = Mutex.new

    def initialize(@app_id : String = "positron")
      load
    end

    def get(key : String, default : JSON::Any? = nil) : JSON::Any
      @mutex.synchronize do
        if @data.has_key?(key)
          @data[key]
        elsif default
          default
        else
          JSON.parse(nil.to_json)
        end
      end
    end

    def set(key : String, value : JSON::Any) : Bool
      @mutex.synchronize do
        @data[key] = value
        save
      end
      true
    rescue ex
      Log.error { "preferences.set failed: #{ex.message}" }
      false
    end

    def remove(key : String) : Bool
      @mutex.synchronize do
        @data.delete(key)
        save
      end
      true
    rescue ex
      Log.error { "preferences.remove failed: #{ex.message}" }
      false
    end

    def clear : Bool
      @mutex.synchronize do
        @data.clear
        save
      end
      true
    rescue ex
      Log.error { "preferences.clear failed: #{ex.message}" }
      false
    end

    def has?(key : String) : Bool
      @mutex.synchronize { @data.has_key?(key) }
    end

    def all : Hash(String, JSON::Any)
      @mutex.synchronize { @data.dup }
    end

    # --- Internals ---

    private def storage_key : String
      "positron.preferences.#{@app_id}"
    end

    private def defaults : Void*
      ObjC.send0(ObjC.cls("NSUserDefaults"), ObjC.sel("standardUserDefaults"))
    end

    private def load
      json = ObjC.with_autorelease_pool do
        ObjC.to_s(ObjC.send1(defaults, ObjC.sel("stringForKey:"), ObjC.nsstr(storage_key)))
      end
      return if json.nil? || json.empty?

      parsed = JSON.parse(json)
      hash = parsed.as_h?
      return unless hash

      @mutex.synchronize { @data = hash }
    rescue ex
      Log.error { "preferences.load failed: #{ex.message}" }
    end

    private def save
      ObjC.with_autorelease_pool do
        ObjC.send2(defaults, ObjC.sel("setObject:forKey:"),
          ObjC.nsstr(@data.to_json), ObjC.nsstr(storage_key))
      end
    end
  end
end
