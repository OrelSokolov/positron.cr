require "../src/positron"
# dispatch_command comes from spec/plugins_spec.cr (all spec files are
# compiled into one program by `crystal spec`).
require "spec"
require "json"

# The Android async plumbing is platform-pure Crystal (a registry and
# adapter-base overloads); only the JNI calls inside the real adapters
# are device-only. What compiles headless is spec'd here.
require "../src/positron/adapters/android/async_bridge"
require "../src/positron/plugins/file_picker/saf_mime"
require "../src/positron/plugins/save_file_dialog/adapter"
require "../src/positron/plugins/dialogs/adapter"

# Blocking adapters resolve the callback form inline — the desktop
# adapters keep their sync implementations untouched.
class SyncPicker < Positron::Plugins::FilePickerAdapter
  def pick(accept : String) : String?
    "/tmp/picked.txt"
  end
end

class SyncDialogs < Positron::Plugins::DialogsAdapter
  def alert(message : String, title : String, kind : String) : Nil
  end

  def confirm(message : String, title : String) : Bool
    true
  end

  def prompt(message : String, default : String, title : String) : String?
    default
  end
end

class SyncSave < Positron::Plugins::SaveFileDialogAdapter
  def save(suggested_name : String, content : String) : String?
    "/tmp/#{suggested_name}"
  end
end

describe Positron::Adapters::Android::AsyncBridge do
  it "delivers payloads to the registered continuation" do
    delivered = [] of String
    seq = Positron::Adapters::Android::AsyncBridge.start do |payload|
      delivered << payload
    end

    Positron::Adapters::Android::AsyncBridge.complete(seq, %({"seq":#{seq},"ok":true}))
    delivered.should eq([%({"seq":#{seq},"ok":true})])
    Positron::Adapters::Android::AsyncBridge.pending_count.should eq(0)
  end

  it "hands out monotonic, never-reused seqs" do
    a = Positron::Adapters::Android::AsyncBridge.start { |_p| }
    b = Positron::Adapters::Android::AsyncBridge.start { |_p| }
    b.should be > a

    Positron::Adapters::Android::AsyncBridge.cancel(a)
    Positron::Adapters::Android::AsyncBridge.cancel(b)
    Positron::Adapters::Android::AsyncBridge.complete(a, "{}").should be_false
  end

  it "rejects stale completions" do
    seq = Positron::Adapters::Android::AsyncBridge.start { |_p| }
    Positron::Adapters::Android::AsyncBridge.complete(seq, "{}").should be_true
    # Duplicate delivery of the same result must be a no-op.
    Positron::Adapters::Android::AsyncBridge.complete(seq, "{}").should be_false
  end
end

describe "adapter callback overloads" do
  it "pick(accept, &) calls back with the sync result" do
    result = nil.as(String?)
    SyncPicker.new.pick(".txt") { |path| result = path }
    result.should eq("/tmp/picked.txt")
  end

  it "confirm/prompt callback forms call back inline" do
    confirmed = false
    SyncDialogs.new.confirm("m", "t") { |ok| confirmed = ok }
    confirmed.should be_true

    text = nil.as(String?)
    SyncDialogs.new.prompt("m", "fallback", "t") { |value| text = value }
    text.should eq("fallback")
  end

  it "save callback form calls back inline" do
    result = nil.as(String?)
    SyncSave.new.save("out.txt", "data") { |path| result = path }
    result.should eq("/tmp/out.txt")
  end
end

describe Positron::Plugins::SafMime do
  it "maps accept filters to a single SAF MIME type" do
    mime = Positron::Plugins::SafMime
    mime.mime_for(".png").should eq("image/png")
    mime.mime_for(".jpg,.jpeg").should eq("image/jpeg")
    mime.mime_for("text/plain").should eq("text/plain")
    # Mixed or unknown filters fall back to everything.
    mime.mime_for(".png,.txt").should eq("*/*")
    mime.mime_for("*").should eq("*/*")
    mime.mime_for("").should eq("*/*")
  end
end

describe Positron::Plugins::Permissions do
  it "keeps desktop granted semantics through the adapter" do
    {% if !flag?(:android) %}
      plugin = Positron::Plugins::Permissions.new

      check = dispatch_command(plugin, "permissions.check", {"permission" => "camera"})
      check.data["state"].as_s.should eq("granted")

      request = dispatch_command(plugin, "permissions.request", {"permission" => "camera"})
      request.data["state"].as_s.should eq("granted")
    {% end %}
  end
end
