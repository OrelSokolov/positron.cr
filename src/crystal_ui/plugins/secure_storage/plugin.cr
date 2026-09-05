require "json"
require "log"
require "file_utils"
require "./crypto"

module CrystalUI::Plugins
  # Secure storage plugin — encrypted key-value store for tokens,
  # passwords and certificates.
  #
  # Exposes to the frontend:
  #   - secure_storage.set(key, value)
  #   - secure_storage.get(key)   → String | null
  #   - secure_storage.remove(key)
  #   - secure_storage.has(key)
  #   - secure_storage.clear()
  #
  # Storage file layout (binary, little-endian, written atomically):
  #
  #   "CUSS1" magic (5) | salt (16) | iv (16) | mac (32) | ciphertext
  #
  # - Payload: AES-256-CBC encrypted JSON map, authenticated with
  #   encrypt-then-MAC HMAC-SHA256 (see `SecureStorageCrypto`).
  # - Key: PBKDF2-HMAC-SHA256(passphrase, salt, 600_000, 32 bytes).
  # - Passphrase: `CRYSTAL_UI_STORAGE_KEY` env var if set, otherwise a
  #   random 32-byte key generated once per install next to the store
  #   (0600 permissions).
  #
  # Threat model (be honest about what this is): secrets are not readable
  # from a plain `cat` of the data file, and the macOS Keychain / Linux
  # secret service / Windows credential manager remain the right answer
  # for multi-user machines. A libsecret adapter can slot in later behind
  # the same plugin API.
  class SecureStorage < CrystalUI::Plugin
    MAGIC = "CUSS1"

    @passphrase : Bytes?

    def initialize(@app_id : String = "crystalui")
    end

    def name : String
      "secure_storage"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      key_arg = CrystalUI::ArgumentManifest.new(name: "key", type: "String")

      {
        "secure_storage.set" => CrystalUI::CommandManifest.new(
          name: "secure_storage.set",
          args: [
            key_arg,
            CrystalUI::ArgumentManifest.new(name: "value", type: "String"),
          ],
          returns: "Bool",
        ),
        "secure_storage.get" => CrystalUI::CommandManifest.new(
          name: "secure_storage.get",
          args: [key_arg],
          returns: "String",
        ),
        "secure_storage.remove" => CrystalUI::CommandManifest.new(
          name: "secure_storage.remove",
          args: [key_arg],
          returns: "Bool",
        ),
        "secure_storage.has" => CrystalUI::CommandManifest.new(
          name: "secure_storage.has",
          args: [key_arg],
          returns: "Bool",
        ),
        "secure_storage.clear" => CrystalUI::CommandManifest.new(
          name: "secure_storage.clear",
          returns: "Bool",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("secure_storage.set") do |request|
        values = load
        values[str(request.args, "key")] = str(request.args, "value")
        save(values)
        CrystalUI::CommandResult.new(
          success: true, data: JSON.parse(true.to_json))
      end

      registry.register("secure_storage.get") do |request|
        value = load[str(request.args, "key")]?
        CrystalUI::CommandResult.new(
          success: true,
          data: value.nil? ? JSON.parse("null") : JSON.parse(value.to_json)
        )
      end

      registry.register("secure_storage.remove") do |request|
        values = load
        existed = values.delete(str(request.args, "key")) ? true : false
        save(values) if existed
        CrystalUI::CommandResult.new(
          success: true, data: JSON.parse(existed.to_json))
      end

      registry.register("secure_storage.has") do |request|
        existed = load.has_key?(str(request.args, "key"))
        CrystalUI::CommandResult.new(
          success: true, data: JSON.parse(existed.to_json))
      end

      registry.register("secure_storage.clear") do |_request|
        save({} of String => String)
        CrystalUI::CommandResult.new(
          success: true, data: JSON.parse(true.to_json))
      end
    end

    # --- Storage file handling ---

    private def load : Hash(String, String)
      return {} of String => String unless File.exists?(store_path)

      raw = File.read(store_path)
      return {} of String => String if raw.bytesize <= HEADER_SIZE

      salt = raw.to_slice[5, 16]
      iv = raw.to_slice[21, 16]
      mac = raw.to_slice[37, 32]
      ciphertext = raw.to_slice[HEADER_SIZE..]

      key = derive_key(salt)
      verify(mac, key, iv, ciphertext)

      JSON.parse(String.new(SecureStorageCrypto.decrypt(key, iv, ciphertext)))
        .as_h.reduce({} of String => String) do |acc, (k, v)|
          acc[k] = v.as_s? || v.to_s
          acc
        end
    rescue ex
      Log.for("crystalui.plugins.secure_storage").error {
        "store unreadable (wrong key or corrupt file): #{ex.message}"
      }
      {} of String => String
    end

    private def save(values : Hash(String, String)) : Nil
      FileUtils.mkdir_p(File.dirname(store_path))

      salt = SecureStorageCrypto.random_bytes(16)
      key = derive_key(salt)
      iv, ciphertext = SecureStorageCrypto.encrypt(key, values.to_json.to_slice)
      mac = SecureStorageCrypto.hmac_sha256(key, iv + ciphertext)

      File.open(store_path, "w") do |io|
        io.write(MAGIC.to_slice)
        io.write(salt)
        io.write(iv)
        io.write(mac)
        io.write(ciphertext)
      end

      File.chmod(store_path, 0o600)
    end

    HEADER_SIZE = 5 + 16 + 16 + 32

    private def verify(mac : Bytes, key : Bytes, iv : Bytes, ciphertext : Bytes) : Nil
      computed = SecureStorageCrypto.hmac_sha256(key, iv + ciphertext)
      raise "MAC mismatch" unless SecureStorageCrypto.constant_time_equal?(mac, computed)
    end

    private def derive_key(salt : Bytes) : Bytes
      SecureStorageCrypto.pbkdf2_sha256(
        passphrase, salt, SecureStorageCrypto::ITERATIONS, 32)
    end

    # Env passphrase, or a per-install random key stored next to the data
    # file (0600) — created on first use.
    private def passphrase : Bytes
      @passphrase ||= ENV["CRYSTAL_UI_STORAGE_KEY"]?.try(&.to_slice) || begin
        FileUtils.mkdir_p(File.dirname(store_path))
        if File.exists?(key_path)
          File.read(key_path).to_slice
        else
          key = SecureStorageCrypto.random_bytes(32)
          File.write(key_path, key)
          File.chmod(key_path, 0o600)
          key
        end
      end
    end

    private def store_path : String
      base = ENV["XDG_DATA_HOME"]? || File.join(ENV["HOME"]? || "/", ".local", "share")
      File.join(base, @app_id, "secure-storage.bin")
    end

    private def key_path : String
      store_path + ".key"
    end

    private def str(args : JSON::Any, key : String) : String
      args[key]?.try(&.as_s?) || ""
    end
  end
end
