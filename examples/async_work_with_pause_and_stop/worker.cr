require "../../src/positron"

# The demo's core, isolated from the app so the spec can exercise it
# headlessly (same pattern as async_progress/worker.cr).
#
# A token-aware job: it advances `total` units (one per second) and
# sleeps through `Token#sleep` — so the job can be paused (the sleep
# parks while paused) and stopped (the sleep/checkpoint raises
# AsyncWork::Cancelled the moment cancel! flips the token). Each
# completed unit is reported via `on_progress`.
module PauseStopDemo
  record Result,
    units_done : Int32,
    cancelled : Bool,
    elapsed_ms : Float64

  # Runs ~`total` seconds (one unit per second). Returns normally when
  # all units complete, or with cancelled=true when the token was
  # cancelled — Cancelled is raised inside token.sleep and caught here,
  # so callers never see the exception itself.
  def self.run(total : Int32, token : Positron::AsyncWork::Token,
               &on_progress : Int32 -> _) : Result
    t0 = Time.instant
    done = 0
    cancelled = false

    begin
      loop do
        token.sleep(1.second)
        done += 1
        on_progress.call(done)
        break if done >= total
      end
    rescue ex : Positron::AsyncWork::Cancelled
      cancelled = true
    end

    Result.new(
      units_done: done,
      cancelled: cancelled,
      elapsed_ms: (Time.instant - t0).total_milliseconds
    )
  end
end
