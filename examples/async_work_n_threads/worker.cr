require "../../src/positron"

# The demo's core, isolated from the app so specs can exercise it
# headlessly (same pattern as async_progress/worker.cr).
#
# One CPU-bound job split between N `async_work_n_threads` workers:
# each worker gets an equal static slice (by its index) of
# TOTAL_UNITS positions, hashes them and returns the XOR of its
# per-position hashes. XOR is order-independent, so the combined
# checksum is identical for any worker count — the spec relies on
# that, and so does the UI (a run is comparable to any other run).
module NThreadsDemo
  TOTAL_UNITS = 300_000_000_i64
  CHUNK       =   1_000_000_i64

  # Reference-wrapped atomic counter. Atomic itself is a struct:
  # returning one from .start would hand the caller a snapshot copy
  # while worker closures keep mutating the original (captured box) —
  # a class keeps everyone on the same object.
  class Counter
    def initialize
      @value = Atomic(Int64).new(0)
    end

    def add(units : Int64) : Nil
      @value.add(units)
    end

    def get : Int64
      @value.get
    end
  end

  # The per-unit CPU burn: a short latency-chained LCG (8 dependent
  # multiplies — cannot be vectorized away), so one unit costs real
  # cycles and the parallel speedup is measurable.
  def self.unit_hash(pos : Int64) : Int64
    h = pos &+ 1
    8.times do
      h = h &* 6364136223846793005_i64 &+ 1442695040888963407_i64
    end
    h
  end

  # XOR of unit_hash over [from, from + count) — one worker's slice.
  # Cancels at chunk boundaries via token.checkpoint!; each completed
  # chunk is reported through the block (note: Atomic is a struct —
  # pass-by-value in Crystal — so the counter must be mutated through
  # a closure that captures it, not handed over as an argument).
  def self.burn_range(from : Int64, count : Int64,
                      token : Positron::AsyncWork::Token,
                      &on_chunk : Int64 -> _) : Int64
    checksum = 0_i64
    pos = from
    stop = from &+ count
    while pos < stop
      n = {CHUNK, stop - pos}.min
      n.times { |k| checksum ^= unit_hash(pos &+ k) }
      on_chunk.call(n)
      pos &+= n
      token.checkpoint!
    end
    checksum
  end

  # The full job for one worker set: splits total evenly (the last
  # worker takes the remainder), runs the slices on
  # async_work_n_threads. Returns {job, progress} — the caller polls
  # progress and uses the job handle to pause/cancel while it runs.
  def self.start(total : Int64, workers : Int32)
    progress = Counter.new

    job = Positron.async_work_n_threads(name: "nthreads-burn", threads: workers) do |token, index|
      slice = total // workers
      from = index.to_i64 &* slice
      count = index == workers - 1 ? total - from : slice
      burn_range(from, count, token) { |n| progress.add(n) }
    end

    {job, progress}
  end

  # The reference checksum for a range, computed inline (specs compare
  # multi-worker results against it).
  def self.checksum(total : Int64) : Int64
    burn_range(0_i64, total, Positron::AsyncWork::Token.new) { |_n| nil }
  end
end
