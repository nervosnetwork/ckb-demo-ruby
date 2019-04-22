# frozen_string_literal: true

require "secp256k1"
require "securerandom"

module Ckb
	class Key
    attr_reader :privkey, :pubkey

    # @param privkey [String] hex string
    def initialize(privkey)
      raise ArgumentError, "invalid privkey!" unless privkey.instance_of?(String) && privkey.size == 66

      raise ArgumentError, "invalid hex string!" unless Ckb::Utils.valid_hex_string?(privkey)

      @privkey = privkey

      @pubkey = self.class.pubkey(@privkey)
    end

    def pubkey_hash
      pubkey_bin = Ckb::Utils.hex_to_bin(@pubkey)
      pubkey_hash_bin = Ckb::Blake2b.digest(Ckb::Blake2b.digest(pubkey_bin))
      Utils.bin_to_hex(pubkey_hash_bin)
    end

    def self.random_private_key
      Ckb::Utils.bin_to_hex(SecureRandom.bytes(32))
    end

    def self.pubkey(privkey)
      privkey_bin = [privkey[2..-1]].pack("H*")
      pubkey_bin = Secp256k1::PrivateKey.new(privkey: privkey_bin).pubkey.serialize
      Utils.bin_to_hex(pubkey_bin)
    end
	end
end
