require "json"
require "./adapter"

module Positron::Plugins
  # Android implementation of persistent preferences.
  #
  # This is a host-side stub that keeps preferences in memory for the
  # application session. A future iteration should bridge to Android
  # SharedPreferences through the JNI shim.
  class AndroidPreferencesAdapter < PreferencesAdapter
    @data = {} of String => JSON::Any
    @mutex = Mutex.new

    def initialize(@app_id : String = "positron")
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
      @mutex.synchronize { @data[key] = value }
      true
    end

    def remove(key : String) : Bool
      @mutex.synchronize { @data.delete(key); true }
    end

    def clear : Bool
      @mutex.synchronize { @data.clear; true }
    end

    def has?(key : String) : Bool
      @mutex.synchronize { @data.has_key?(key) }
    end

    def all : Hash(String, JSON::Any)
      @mutex.synchronize { @data.dup }
    end
  end
end
