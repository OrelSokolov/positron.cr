module Positron
  module Adapters
    module Android
      # Registry for asynchronous native roundtrips (SAF picks, native
      # dialogs, …).
      #
      # The Android adapters cannot block the GUI fiber: it is the
      # event-loop pump, and the result of e.g. a SAF picker arrives
      # through that same pump (Java `nativeEvent` → shim queue →
      # `Host#drain_shim_events`). So an adapter registers a
      # continuation under a fresh `seq`, starts the native request
      # through the JNI bridge, and returns immediately; the host's
      # event drain later calls `.complete` with the raw JSON payload
      # on the GUI fiber, which resolves the parked command fiber
      # through its channel.
      #
      # Threading: `.start` is called from the GUI fiber (adapters run
      # inside `Host#run_on_main`), `.complete` too (shim-event drain).
      # No locking needed, but a mutex keeps it safe if that ever
      # changes.
      module AsyncBridge
        @@seq = 0
        @@pending = {} of Int32 => Proc(String, Nil)
        @@mutex = Mutex.new

        # Register a continuation; returns its seq (monotonic, never
        # reused). The block receives the raw JSON payload string of the
        # matching result event and runs on the GUI fiber.
        def self.start(&on_done : String ->) : Int32
          @@mutex.synchronize do
            seq = (@@seq += 1)
            @@pending[seq] = on_done
            seq
          end
        end

        # Drop a continuation without running it (the native side
        # refused to even start the request).
        def self.cancel(seq : Int32) : Nil
          @@mutex.synchronize { @@pending.delete(seq) }
        end

        # Deliver a result payload. Returns false when nothing is
        # registered under `seq` (stale/duplicate event).
        def self.complete(seq : Int32, payload : String) : Bool
          callback = @@mutex.synchronize { @@pending.delete(seq) }
          return false unless callback
          callback.call(payload)
          true
        end

        # Number of roundtrips still awaiting a native result.
        def self.pending_count : Int32
          @@mutex.synchronize { @@pending.size }
        end
      end
    end
  end
end
