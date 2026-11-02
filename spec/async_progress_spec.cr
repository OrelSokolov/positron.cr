require "../examples/async_progress/worker"
require "spec"

# The async progress demo's core claims, exercised headlessly:
#
#   1. the job reports progress once per second with elapsed t and t²;
#   2. the final result matches the last progress tick;
#   3. the job waits (it is async_work material — IO/waits, not a
#      tight loop), so the runtime is free while it runs.
describe AsyncProgressDemo do
  it "reports elapsed seconds and their squares every second" do
    ticks = [] of {Int32, Int32}

    result = AsyncProgressDemo.run(3) { |elapsed, square| ticks << {elapsed, square} }

    ticks.should eq([{1, 1}, {2, 4}, {3, 9}])
    result.elapsed.should eq(3)
    result.square.should eq(9)
  end

  it "does not block other fibers while waiting" do
    ticks = 0
    spawn do
      20.times do
        sleep 50.milliseconds
        ticks += 1
      end
    end

    AsyncProgressDemo.run(2) { |_e, _s| nil }

    # ~2 s of sleeping work with 50 ms ticks nearby: the ticker must
    # have interleaved freely.
    ticks.should be >= 20
  end
end
