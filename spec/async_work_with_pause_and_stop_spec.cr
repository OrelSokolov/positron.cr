require "../examples/async_work_with_pause_and_stop/worker"
require "spec"

# The pause/stop demo's core claims, exercised headlessly:
#
#   1. the job completes all units, one per second, when untouched;
#   2. cancel! aborts it at the current unit (Cancelled is raised
#      inside token.sleep and surfaced as cancelled=true);
#   3. pause! parks the job — paused seconds do not count towards the
#      units, so the run stretches by the pause duration.
describe PauseStopDemo do
  it "completes all units when untouched" do
    ticks = [] of Int32

    result = PauseStopDemo.run(2, Positron::AsyncWork::Token.new) { |done| ticks << done }

    ticks.should eq([1, 2])
    result.units_done.should eq(2)
    result.cancelled.should be_false
    result.elapsed_ms.should be >= 1900
  end

  it "stop cancels the job at the current unit" do
    token = Positron::AsyncWork::Token.new
    ticks = [] of Int32
    done = Channel(PauseStopDemo::Result).new(1)
    t0 = Time.instant

    spawn do
      done.send(PauseStopDemo.run(10, token) { |units| ticks << units })
    end

    # Wait for the first unit to land (one second of sliced sleep, but
    # slow CI runners stretch it well past 1.4 s), then cancel: the
    # second sleep must raise within a slice (~25 ms), not after the
    # remaining 9 seconds.
    deadline = Time.instant + 10.seconds
    while ticks.empty? && Time.instant <= deadline
      sleep 50.milliseconds
    end
    cancelled_at = Time.instant
    token.cancel!

    result = done.receive
    ticks.should eq([1])
    result.cancelled.should be_true
    result.units_done.should eq(1)
    # The job must end promptly after cancel — not run on. Bound to the
    # cancel moment (plus scheduler slack), not a fixed wall clock.
    result.elapsed_ms.should be < (cancelled_at - t0).total_milliseconds + 500
  end

  it "pause parks the job and resume continues it" do
    token = Positron::AsyncWork::Token.new
    ticks = [] of Int32
    done = Channel(PauseStopDemo::Result).new(1)

    spawn { done.send(PauseStopDemo.run(2, token) { |units| ticks << units }) }

    # Pause during the first second, hold ~1 s, resume: the first unit
    # lands at ~2 s instead of ~1 s, the second at ~3 s.
    sleep 300.milliseconds
    token.pause!
    sleep 1.second
    token.resume!

    result = done.receive
    ticks.should eq([1, 2])
    result.cancelled.should be_false
    # 2 units (~2 s of work) + ~1 s parked: comfortably above 2.8 s.
    result.elapsed_ms.should be >= 2800
  end
end
