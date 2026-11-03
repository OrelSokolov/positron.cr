require "../src/positron/mobile/queue"
require "spec"

describe Positron::Mobile::MessageQueue do
  it "drains blocks oldest first" do
    queue = Positron::Mobile::MessageQueue.new
    order = [] of Int32

    queue.push { order << 1 }
    queue.push { order << 2 }
    queue.push { order << 3 }

    queue.pending?.should be_true
    queue.drain
    order.should eq([1, 2, 3])
    queue.pending?.should be_false
  end

  it "runs only the blocks queued when drain starts" do
    queue = Positron::Mobile::MessageQueue.new
    order = [] of Int32

    queue.push { order << 1 }
    # A block scheduling more work from inside drain must not run in
    # the same pass — the pump stays deadlock-free.
    queue.push { queue.push { order << 3 }; order << 2 }

    queue.drain
    order.should eq([1, 2])
    queue.pending?.should be_true
    queue.drain
    order.should eq([1, 2, 3])
  end

  it "clear drops pending blocks" do
    queue = Positron::Mobile::MessageQueue.new
    ran = false

    queue.push { ran = true }
    queue.clear
    queue.drain

    ran.should be_false
    queue.pending?.should be_false
  end
end
