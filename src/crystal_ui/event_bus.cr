require "json"
require "log"

module CrystalUI
  # Internal pub/sub nervous system of the Crystal Host.
  #
  # EventBus is decoupled from the JS bridge and from native shims.
  # Plugins, adapters and runtime components publish and subscribe to
  # events without knowing about each other.
  module EventBus
    alias Handler = Proc(JSON::Any, Nil)

    @@subscribers = Hash(String, Array(Handler)).new { |h, k| h[k] = [] of Handler }
    @@mutex = Mutex.new

    # Subscribe to an event. Handlers run in their own fiber.
    def self.on(event : String, &handler : JSON::Any ->)
      @@mutex.synchronize do
        @@subscribers[event] << handler
      end
    end

    # Emit an event to all subscribers.
    def self.emit(event : String, payload : JSON::Any | Hash | NamedTuple)
      json = payload.is_a?(JSON::Any) ? payload : JSON.parse(payload.to_json)
      handlers = @@mutex.synchronize { @@subscribers[event]?.dup || [] of Handler }

      handlers.each do |h|
        spawn do
          begin
            h.call(json)
          rescue ex
            Log.error { "EventBus handler error for #{event}: #{ex.message}" }
          end
        end
      end
    end

    # Subscribe once and automatically unsubscribe after first fire.
    def self.once(event : String, &handler : JSON::Any ->)
      wrapper = uninitialized Proc(JSON::Any, Nil)

      wrapper = ->(payload : JSON::Any) do
        handler.call(payload)
        off(event, wrapper)
      end

      on(event, &wrapper)
    end

    # Remove a previously registered handler.
    def self.off(event : String, handler : Handler)
      @@mutex.synchronize do
        @@subscribers[event].delete(handler)
      end
    end
  end
end
