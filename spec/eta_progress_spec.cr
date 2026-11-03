require "../examples/eta_progress/worker"
require "spec"

# The ETA demo's core claims, exercised headlessly:
#
#   1. snapshot math is tqdm-consistent: percent tracks done/total and
#      ETA is remaining units over the smoothed rate;
#   2. with a constant rate (no jitter) the smoothed rate locks onto
#      it, so ETA shrinks to exactly zero at the finish;
#   3. workers with different speeds finish in speed order;
#   4. the waiting never blocks other fibers (async_work material).
describe EtaProgressDemo do
  it "reports tqdm-consistent percent, elapsed, rate and ETA" do
    snapshots = [] of EtaProgressDemo::Snapshot

    total_ms = EtaProgressDemo::Worker.new(1, total: 20, rate: 10.0,
      jitter: false, tick_ms: 100).run { |snap| snapshots << snap }

    snapshots.size.should be > 5
    snapshots.last.done.should eq(20)
    snapshots.last.percent.should eq(100)
    snapshots.last.eta_ms.should eq(0.0)

    # done grows by ~1 unit (10 u/s * 0.1 s) per 100 ms tick
    mid = snapshots[5]
    (4..7).should contain(mid.done)
    mid.rate.should be_close(10.0, 0.5)
    # ETA = (total - done)/rate, elapsed tracks wall clock. Tolerances
    # are generous: loaded CI runners routinely stretch sleeps 20-50%
    # (the failure mode being tested is total starvation, not jitter).
    mid.eta_ms.should be_close((20 - mid.done) / mid.rate * 1000, 400)
    mid.elapsed_ms.should be_close(600, 400)

    total_ms.should be_close(2000, 800)
  end

  it "keeps percent monotonic and ETA shrinking to zero" do
    snaps = [] of EtaProgressDemo::Snapshot
    EtaProgressDemo::Worker.new(2, total: 15, rate: 12.0,
      jitter: true, tick_ms: 80).run { |s| snaps << s }

    percents = snaps.map(&.percent)
    percents.should eq(percents.sort)
    percents.last.should eq(100)

    # Jittery rate can wobble ETA slightly, but the final stretch must
    # converge to zero.
    snaps.last(3).map(&.eta_ms).max.should be <= 1000
  end

  it "finishes workers in speed order when run concurrently" do
    fast_done_at = nil
    slow_done_at = nil
    # ~10 units at 20 u/s (≈0.5 s) vs ~10 units at 4 u/s (≈2.5 s)
    fast = EtaProgressDemo::Worker.new(3, total: 10, rate: 20.0, jitter: false, tick_ms: 100)
    slow = EtaProgressDemo::Worker.new(4, total: 10, rate: 4.0, jitter: false, tick_ms: 100)
    spawn { fast.run { |s| fast_done_at = s.elapsed_ms if s.finished? } }
    spawn { slow.run { |s| slow_done_at = s.elapsed_ms if s.finished? } }
    until fast_done_at && slow_done_at
      sleep 50.milliseconds
    end
    fast_done_at.not_nil!.should be < slow_done_at.not_nil!
  end

  it "does not block other fibers while working" do
    ticks = 0
    spawn do
      30.times do
        sleep 50.milliseconds
        ticks += 1
      end
    end

    EtaProgressDemo::Worker.new(5, total: 10, rate: 10.0,
      jitter: false, tick_ms: 100).run { |_s| nil }

    # ~1 s of sleeping work: the 50 ms ticker must interleave freely.
    # A blocked scheduler scores ~0-2; loaded CI runners stretch sleeps
    # by 2x, so the floor sits well below the healthy count.
    ticks.should be >= 10
  end
end
