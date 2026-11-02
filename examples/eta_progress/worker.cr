require "json"

# The demo's core, isolated from the app so specs can exercise it
# headlessly (same pattern as async_progress/worker.cr).
#
# A tqdm-style worker: it advances `total` units at ~`rate` units per
# second (optional per-tick jitter, so the smoothed rate actually has
# something to smooth) and reports a snapshot on every tick with
# everything a tqdm line shows:
#
#   42%|█████████████░░░░░░░| 42/100 [4.2s<5.8s, 10.0u/s]
#
# The rate is an exponential moving average (tqdm's smoothing=0.3) of
# the instantaneous per-tick rate; ETA is remaining units over that
# smoothed rate.
module EtaProgressDemo
  # One progress report. JSON::Serializable so the app can hand it to
  # `Host#emit_to_js` as-is.
  struct Snapshot
    include JSON::Serializable

    getter id : Int32
    getter done : Int32
    getter total : Int32
    getter percent : Int32
    getter elapsed_ms : Float64
    getter rate : Float64 # smoothed, units/s
    getter eta_ms : Float64

    def initialize(@id, @done, @total, @percent, @elapsed_ms, @rate, @eta_ms)
    end

    def finished? : Bool
      @done >= @total
    end
  end

  class Worker
    getter id : Int32

    def initialize(@id : Int32, @total : Int32, @rate : Float64,
                   @jitter = true, @tick_ms = 200, @alpha = 0.3)
    end

    # Runs until `total` units are done, calling `on_progress` with a
    # snapshot every tick. The last snapshot is the finished one
    # (done == total, percent == 100, eta == 0). Sleeps between ticks —
    # async_work material, the host loop stays free. Returns total
    # elapsed milliseconds.
    def run(&on_progress : Snapshot -> _) : Float64
      t0 = Time.instant
      done = 0.0
      smoothed = 0.0

      while done < @total
        sleep @tick_ms.milliseconds

        factor = @jitter ? rand(0.7..1.3) : 1.0
        step = @rate * (@tick_ms / 1000.0) * factor
        done = {@total.to_f, done + step}.min

        inst_rate = step / (@tick_ms / 1000.0)
        smoothed = smoothed.zero? ? inst_rate : @alpha * inst_rate + (1 - @alpha) * smoothed

        elapsed = (Time.instant - t0).total_milliseconds
        remaining = @total - done
        eta = remaining > 0 && smoothed > 0 ? remaining / smoothed * 1000.0 : 0.0

        on_progress.call(Snapshot.new(
          id: @id,
          done: done.round.to_i,
          total: @total,
          percent: (done / @total * 100).round.to_i,
          elapsed_ms: elapsed.round(1),
          rate: smoothed.round(2),
          eta_ms: eta.round(1)
        ))
      end

      (Time.instant - t0).total_milliseconds
    end
  end
end
