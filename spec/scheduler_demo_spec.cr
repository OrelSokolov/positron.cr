require "../examples/scheduler_demo/burn"
require "spec"
require "path"

# The scheduler demo's core claims, exercised headlessly:
#
#   1. a naive CPU loop starves every other fiber (the freeze);
#   2. periodic Fiber.yield interleaves the burn with other fibers;
#   3. a child-process burn parks the calling fiber off-loop, so
#      other fibers run freely while the work truly happens elsewhere.
describe SchedulerDemo do
  {% if flag?(:unix) %}
    # The freeze claim cannot be asserted inside the spec runtime: the
    # spec framework itself adds fiber yield points (see
    # src/spec/example.cr — signals are only handled on fiber switch,
    # so the runner sprinkles yields), which masks exactly the
    # starvation this example demonstrates. Run the scenario in a
    # clean subprocess instead.
    it "freeze_burn starves other fibers (verified in a clean subprocess)" do
      # Crystal resolves requires relative to the requiring file (not
      # the cwd) and does not support absolute require paths, so the
      # scenario must live inside spec/ for the relative require to
      # resolve. It is deleted afterwards.
      scenario = <<-CR
        require "../examples/scheduler_demo/burn"
        ticks = 0
        ticks_at_end = -1
        done = false
        spawn do
          SchedulerDemo.freeze_burn(1)
          ticks_at_end = ticks
          done = true
        end
        spawn { loop { sleep 50.milliseconds; ticks += 1 } }
        until done
          sleep 10.milliseconds
        end
        puts "ticks_at_end=\#{ticks_at_end}"
      CR

      path = Path[__DIR__].join(".freeze_check_#{Process.pid}.cr").to_s
      File.write(path, scenario)
      output = IO::Memory.new
      begin
        status = Process.run("crystal", {"run", "--no-color", path},
          output: output, error: output, chdir: Path[__DIR__].parent.to_s)
        status.success?.should be_true, "subprocess failed:\n#{output}"
        output.to_s.should contain("ticks_at_end=0")
      ensure
        File.delete(path) rescue nil
      end
    end
  {% end %}

  it "yielding_burn lets other fibers run concurrently" do
    ticks = 0

    spawn do
      SchedulerDemo.yielding_burn(1, slice_ms: 50)
    end
    spawn do
      1_000.times do
        sleep 50.milliseconds
        ticks += 1
      end
    end

    # ~1 s of burn with 50 ms ticks; wait just past it and require a
    # healthy interleaving count.
    sleep 1300.milliseconds
    ticks.should be >= 10
  end

  it "isolated_burn runs in a child process without blocking fibers" do
    ticks = 0
    spawn do
      20.times do
        sleep 50.milliseconds
        ticks += 1
      end
    end

    result = SchedulerDemo.isolated_burn(1)

    result.should match(/^\d+$/)
    # The burn took ~1 s and the ticker fired every 50 ms off-loop:
    # most ticks must have landed while the child was spinning.
    ticks.should be >= 10
  end
end
