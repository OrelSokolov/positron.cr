require "time"

# Scheduler demo core: three ways to run a multi-second CPU burn
# against Crystal's cooperative single-threaded scheduler.
#
# The catch being demonstrated: fibers never preempt each other, so a
# tight CPU loop blocks the whole event loop — including the GTK main
# loop in a positron host — even though commands dispatch in fibers.
#
#   freeze_burn   — naive loop, blocks everything (the anti-pattern).
#   yielding_burn — the same loop with a periodic Fiber.yield: the
#                   scheduler interleaves it with other work; the loop
#                   must be under your control.
#   isolated_burn — the burn runs in a child process; Process.run
#                   parks the calling fiber off-loop, so the host
#                   stays responsive and the work truly runs in
#                   parallel. Use this for blocking code you don't
#                   own (the same pattern datasetmaster uses for
#                   arecord and the phonemizer).
#
# Kept in its own file so specs can exercise the helpers without
# running the GUI app (see spec/scheduler_demo_spec.cr).
module SchedulerDemo
  # Naive burn: no yields — blocks the whole event loop.
  def self.freeze_burn(seconds : Int32) : Int64
    iterations = 0_i64
    deadline = Time.instant + seconds.seconds
    while Time.instant < deadline
      50_000.times { iterations &+= 1 }
    end
    iterations
  end

  # Cooperative burn: yields to the scheduler once per slice so other
  # fibers (and the GTK main loop) keep running.
  def self.yielding_burn(seconds : Int32, slice_ms : Int32 = 50) : Int64
    iterations = 0_i64
    deadline = Time.instant + seconds.seconds
    next_yield = Time.instant + slice_ms.milliseconds
    while (now = Time.instant) < deadline
      50_000.times { iterations &+= 1 }
      if now >= next_yield
        Fiber.yield
        next_yield = Time.instant + slice_ms.milliseconds
      end
    end
    iterations
  end

  # Isolated burn: a child shell process spins for the requested time
  # and prints its iteration count. Pure shell arithmetic — zero forks
  # per iteration (a `date`-per-iteration variant fork-storms ~500
  # execs/s and starves the host on small machines, which reads as
  # "host blocked" even though the scheduler is fine). Process.run
  # parks the calling fiber off-loop, so the host stays responsive and
  # the child truly runs in parallel.
  #
  # Unix: bash + the built-in SECONDS counter (1 s granularity, hence
  # the +1). Windows: there is no bash on a stock box — the `bash.exe`
  # stub just prints a WSL error — so the child is a PowerShell loop.
  # Both print a bare iteration count for the spec to match.
  def self.isolated_burn(seconds : Int32) : String
    {% if flag?(:win32) %}
      script = "$e = [DateTime]::UtcNow.AddSeconds(#{seconds} + 1); " +
               "$i = 0; while ([DateTime]::UtcNow -lt $e) { $i++ }; $i"
      stdout_io = IO::Memory.new
      Process.run("powershell", {"-NoProfile", "-Command", script}, output: stdout_io)
      stdout_io.to_s.strip
    {% else %}
      script = %{end=$((SECONDS + #{seconds} + 1)); i=0; } +
               %{while (( SECONDS < end )); do ((i+=1)); done; echo $i}
      stdout_io = IO::Memory.new
      Process.run("bash", {"-c", script}, output: stdout_io)
      stdout_io.to_s.strip
    {% end %}
  end
end
