require_relative "api"
require_relative 'utils'

require "secp256k1"
require "securerandom"

module Ckb
  class Wallet
    attr_reader :api
    attr_reader :privkey

    def initialize(api, privkey)
      unless privkey.instance_of?(String) && privkey.size == 32
        raise ArgumentError, "invalid privkey!"
      end

      @api = api
      @privkey = privkey
    end

    def pubkey
      Secp256k1::PrivateKey.new(privkey: privkey).pubkey.serialize
    end

    def address
      Ckb::Utils.bin_to_hex(api.calculate_redeem_script_hash(pubkey))
    end

    def self.random(api)
      self.new(api, SecureRandom.bytes(32))
    end

    def self.from_hex(api, privkey_hex)
      self.new(api, Ckb::Utils.hex_to_bin(privkey_hex))
    end
  end
end
