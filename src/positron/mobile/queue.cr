module Positron
  module Mobile
    # Fiber-safe work queue for mobile hosts.
    #
    # On mobile the OS owns the main loop and there is no native idle
    # source to piggyback on (unlike the desktop GLib/Win32 loops).
    # The host thread runs a pump that drains this queue on the GUI
    # fiber; any Crystal fiber can push work onto it via `run_on_main`.
    #
    # GC safety (same rule as `EventLoop::Linux#run_on_main`): the
    # closures live in this GC-scanned Deque for as long as they may
    # run, and nothing GC-heap-backed ever crosses an FFI boundary —
    # entries coming from raw native threads arrive through the C shim
    # as plain copied strings instead (see `adapters/android/jni.cr`).
    class MessageQueue
      @mutex = Mutex.new
      @pending = Deque(->).new

      # Queue a block for execution on the GUI fiber. Safe to call from
      # any Crystal fiber; NOT from a raw native (JNI) thread — those
      # cannot touch the Crystal heap.
      def push(&block : ->) : Nil
        @mutex.synchronize { @pending << block }
      end

      # True when at least one block is waiting.
      def pending? : Bool
        @mutex.synchronize { !@pending.empty? }
      end

      # Run every block queued at the moment of the call, oldest first.
      # Blocks pushed while draining (including by the blocks
      # themselves) stay queued for the next drain — the pump cannot be
      # starved by a self-feeding producer.
      def drain : Nil
        count = @mutex.synchronize { @pending.size }
        count.times do
          block = @mutex.synchronize { @pending.shift? } || break
          block.call
        end
      end

      # Drop everything still queued (used on host teardown).
      def clear : Nil
        @mutex.synchronize { @pending.clear }
      end
    end
  end
end
