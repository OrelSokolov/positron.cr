require "../src/crystal_ui"
require "spec"
require "json"
require "file_utils"

def temp_dir : String
  dir = File.join(Dir.tempdir, "crystalui-spec-#{Random::Secure.hex(6)}")
  FileUtils.mkdir_p(dir)
  dir
end

# Dispatch a command against a freshly bound plugin.
def dispatch_command(plugin : CrystalUI::Plugin, name : String, args = {} of String => JSON::Any)
  registry = CrystalUI::CommandRegistry.new
  state = CrystalUI::StateManager.new
  plugin.bind(registry, state)
  request = CrystalUI::CommandRequest.new(
    id: "spec", name: name, args: JSON.parse(args.to_json))
  registry.dispatch(request)
end

describe CrystalUI::Plugins::Filesystem do
  it "writes, reads, lists and stats files" do
    dir = temp_dir()
    plugin = CrystalUI::Plugins::Filesystem.new(root: dir)

    write = dispatch_command(plugin, "fs.write", {"path" => "notes/todo.txt", "content" => "hello"})
    write.success.should be_true

    read = dispatch_command(plugin, "fs.read", {"path" => "notes/todo.txt"})
    read.data.as_s.should eq("hello")

    exists = dispatch_command(plugin, "fs.exists", {"path" => "notes/todo.txt"})
    exists.data.as_bool.should be_true

    listing = dispatch_command(plugin, "fs.list", {"path" => "notes"})
    listing.data.as_a.first["name"].as_s.should eq("todo.txt")

    stat = dispatch_command(plugin, "fs.stat", {"path" => "notes/todo.txt"})
    stat.data["size"].as_i.should eq(5)

    removed = dispatch_command(plugin, "fs.remove", {"path" => "notes/todo.txt"})
    removed.data.as_bool.should be_true

    FileUtils.rm_rf(dir)
  end

  it "rejects paths outside the sandbox root" do
    dir = temp_dir()
    plugin = CrystalUI::Plugins::Filesystem.new(root: dir)

    result = dispatch_command(plugin, "fs.write", {"path" => "../escape.txt", "content" => "no"})
    result.success.should be_false
    result.error.not_nil!.should contain("sandbox")

    FileUtils.rm_rf(dir)
  end

  it "reports XDG-aware app dirs" do
    plugin = CrystalUI::Plugins::Filesystem.new(app_id: "specapp")
    plugin.app_data_dir.should contain("specapp")
    plugin.app_cache_dir.should contain("specapp")
  end
end

# SecureStorageCrypto lives in the unix-only secure_storage plugin (it links
# OpenSSL), so these specs are flag-gated like the SecureStorage ones below.
{% if flag?(:unix) %}
  describe CrystalUI::Plugins::SecureStorageCrypto do
    it "computes HMAC-SHA256 correctly (RFC 4231 test case 2)" do
      key = Bytes.new(20, 0x0b)
      message = "Hi There".to_slice

      digest = CrystalUI::Plugins::SecureStorageCrypto.hmac_sha256(key, message)
      digest.hexstring.should eq(
        "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    end

    it "derives deterministic keys that differ per salt" do
      crypto = CrystalUI::Plugins::SecureStorageCrypto

      a1 = crypto.pbkdf2_sha256("password".to_slice, "saltA".to_slice, 100, 32)
      a2 = crypto.pbkdf2_sha256("password".to_slice, "saltA".to_slice, 100, 32)
      b = crypto.pbkdf2_sha256("password".to_slice, "saltB".to_slice, 100, 32)

      a1.should eq(a2)
      a1.should_not eq(b)
      a1.size.should eq(32)
    end

    it "encrypts and decrypts round-trip" do
      crypto = CrystalUI::Plugins::SecureStorageCrypto
      key = crypto.pbkdf2_sha256("k".to_slice, "s".to_slice, 10, 32)

      iv, ciphertext = crypto.encrypt(key, "secret payload".to_slice)
      (String.new(ciphertext).includes?("secret payload")).should be_false

      plain = crypto.decrypt(key, iv, ciphertext)
      String.new(plain).should eq("secret payload")
    end
  end
{% end %}

{% if flag?(:unix) %}
  describe CrystalUI::Plugins::SecureStorage do
    it "stores and retrieves secrets across plugin instances" do
      data_home = temp_dir()
      old_data = ENV["XDG_DATA_HOME"]?
      old_key = ENV["CRYSTAL_UI_STORAGE_KEY"]?
      ENV["XDG_DATA_HOME"] = data_home
      ENV["CRYSTAL_UI_STORAGE_KEY"] = "spec-passphrase"

      plugin = CrystalUI::Plugins::SecureStorage.new(app_id: "specapp")

      set = dispatch_command(plugin, "secure_storage.set", {"key" => "token", "value" => "abc123"})
      set.data.as_bool.should be_true

      get = dispatch_command(plugin, "secure_storage.get", {"key" => "token"})
      get.data.as_s.should eq("abc123")

      # Fresh instance reads the same persisted store.
      reloaded = dispatch_command(CrystalUI::Plugins::SecureStorage.new(app_id: "specapp"),
        "secure_storage.get", {"key" => "token"})
      reloaded.data.as_s.should eq("abc123")

      has = dispatch_command(plugin, "secure_storage.has", {"key" => "token"})
      has.data.as_bool.should be_true

      removed = dispatch_command(plugin, "secure_storage.remove", {"key" => "token"})
      removed.data.as_bool.should be_true

      gone = dispatch_command(plugin, "secure_storage.get", {"key" => "token"})
      gone.data.to_json.should eq("null")

      # The stored file must not contain the secret in plaintext.
      stored = File.read(File.join(data_home, "specapp", "secure-storage.bin"))
      stored.should_not contain("abc123")

      ENV["XDG_DATA_HOME"] = old_data
      ENV["CRYSTAL_UI_STORAGE_KEY"] = old_key
      FileUtils.rm_rf(data_home)
    end
  end
{% end %}

{% if flag?(:unix) %}
  describe CrystalUI::Plugins::DeepLinks do
    it "grants the socket to the first instance only" do
      runtime_dir = temp_dir()
      old_runtime = ENV["XDG_RUNTIME_DIR"]?
      ENV["XDG_RUNTIME_DIR"] = runtime_dir

      first = CrystalUI::Plugins::DeepLinks.new(app_id: "specapp")
      first.single_instance?.should be_true

      # The socket exists and answers connections.
      sock_path = File.join(runtime_dir, "crystalui-specapp.sock")
      File.exists?(sock_path).should be_true
      client = UNIXSocket.new(sock_path)
      client.close

      # A second instance with the same app id loses the handshake.
      second = CrystalUI::Plugins::DeepLinks.new(app_id: "specapp")
      second.single_instance?.should be_false

      ENV["XDG_RUNTIME_DIR"] = old_runtime
      FileUtils.rm_rf(runtime_dir)
    end

    it "collects scheme URLs from argv" do
      old_argv = ARGV.dup
      runtime_dir = temp_dir()
      old_runtime = ENV["XDG_RUNTIME_DIR"]?
      ENV["XDG_RUNTIME_DIR"] = runtime_dir
      ARGV.replace(["myapp://open/x", "--flag", "myapp://open/y"])

      plugin = CrystalUI::Plugins::DeepLinks.new(app_id: "specapp2", scheme: "myapp")
      plugin.pending.should eq(["myapp://open/x", "myapp://open/y"])

      ARGV.replace(old_argv)
      ENV["XDG_RUNTIME_DIR"] = old_runtime
      FileUtils.rm_rf(runtime_dir)
    end
  end
{% end %}
