require "json"
require "./adapter"

module CrystalUI::Plugins
  # Windows implementation of persistent preferences.
  #
  # Stores values as JSON in `%APPDATA%/<app_id>/preferences.json`.
  # A future iteration may use the Windows registry instead.
  class WindowsPreferencesAdapter < PreferencesAdapter
    @data = {} of String => JSON::Any
    @mutex = Mutex.new

    def initialize(@app_id : String = "crystalui")
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

    private def config_dir : String
      appdata = ENV["APPDATA"]? || Dir.tempdir
      File.join(appdata, @app_id)
    end

    private def preferences_file : String
      File.join(config_dir, "preferences.json")
    end

    private def load
      path = preferences_file
      return unless File.exists?(path)

      content = File.read(path)
      return if content.empty?

      parsed = JSON.parse(content)
      hash = parsed.as_h?
      return unless hash

      @mutex.synchronize { @data = hash }
    rescue ex
      Log.error { "preferences.load failed: #{ex.message}" }
    end

    private def save
      Dir.mkdir_p(config_dir)
      File.write(preferences_file, @data.to_json)
    end
  end
end
