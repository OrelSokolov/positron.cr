# The demo's core, isolated from the app so the spec can exercise it
# headlessly (same pattern as scheduler_demo/burn.cr).
#
# The job simply waits `seconds` seconds, reporting progress every
# second: the elapsed second and its square (t и t²). The callback
# keeps the module UI-free — the app wires it to `emit_to_js`, the
# spec counts calls.
module AsyncProgressDemo
  record Result, elapsed : Int32, square : Int32

  # Runs ~`seconds` seconds. Calls `on_progress` once per second with
  # (elapsed, elapsed²), returns the final result. Sleeps only — the
  # host loop stays free, which is exactly the async_work contract.
  def self.run(seconds : Int32 = 10, &on_progress : Int32, Int32 -> _) : Result
    elapsed = 0
    while elapsed < seconds
      sleep 1.second
      elapsed += 1
      on_progress.call(elapsed, elapsed * elapsed)
    end
    Result.new(elapsed: elapsed, square: elapsed * elapsed)
  end
end
