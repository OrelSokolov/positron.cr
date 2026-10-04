require "digest/sha256"
require "openssl"

module Positron::Plugins
  # Crypto helpers for the secure storage plugin.
  #
  # Authenticated encryption over AES-256-CBC (encrypt-then-MAC with
  # HMAC-SHA256) and PBKDF2-HMAC-SHA256 key derivation, implemented with
  # the Crystal standard library only.
  module SecureStorageCrypto
    # PBKDF2-HMAC-SHA256 (RFC 2898 / RFC 8018).
    ITERATIONS = 100_000

    def self.pbkdf2_sha256(password : Bytes, salt : Bytes,
                           iterations : Int32, key_size : Int32) : Bytes
      output = Bytes.new(key_size)
      block_index = 1_u32

      offset = 0
      while offset < key_size
        block = Bytes.new(4)
        block[0] = (block_index >> 24).to_u8
        block[1] = (block_index >> 16).to_u8
        block[2] = (block_index >> 8).to_u8
        block[3] = block_index.to_u8

        u = hmac_sha256(password, salt + block)
        t = u.dup

        (iterations - 1).times do
          u = hmac_sha256(password, u)
          t.each_index { |i| t[i] ^= u[i] }
        end

        chunk = {key_size - offset, t.size}.min
        (t.to_unsafe + 0).copy_to(output.to_unsafe + offset, chunk)
        block_index += 1
        offset += chunk
      end

      output
    end

    # One-shot HMAC-SHA256.
    def self.hmac_sha256(key : Bytes, message : Bytes) : Bytes
      block_size = 64
      key = digest_one_block(key, block_size)

      ipad = Bytes.new(block_size) { |i| key[i] ^ 0x36_u8 }
      opad = Bytes.new(block_size) { |i| key[i] ^ 0x5c_u8 }

      inner = Digest::SHA256.new
      inner.update(ipad)
      inner.update(message)

      outer = Digest::SHA256.new
      outer.update(opad)
      outer.update(inner.final)

      outer.final
    end

    # Keys longer than the hash block size are replaced by their digest.
    private def self.digest_one_block(key : Bytes, block_size : Int32) : Bytes
      return key if key.size == block_size

      if key.size > block_size
        Digest::SHA256.digest(key)
      else
        padded = Bytes.new(block_size)
        padded.copy_from(key)
        padded
      end
    end

    # Encrypt with AES-256-CBC. Returns `{iv, ciphertext}` — the CBC IV is
    # random per call and travels with the payload.
    def self.encrypt(key : Bytes, plaintext : Bytes) : {Bytes, Bytes}
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt
      cipher.key = key
      iv = cipher.random_iv
      {iv, cipher.update(plaintext) + cipher.final}
    end

    def self.decrypt(key : Bytes, iv : Bytes, ciphertext : Bytes) : Bytes
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = key
      cipher.iv = iv
      cipher.update(ciphertext) + cipher.final
    end

    def self.random_bytes(size : Int32) : Bytes
      Random::Secure.random_bytes(size)
    end

    # Constant-time equality for MAC comparison.
    def self.constant_time_equal?(a : Bytes, b : Bytes) : Bool
      return false if a.size != b.size
      diff = 0_u8
      a.zip(b) { |x, y| diff |= x ^ y }
      diff == 0
    end
  end
end
