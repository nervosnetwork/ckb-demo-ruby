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
      Ckb::Utils.bin_to_hex(redeem_script_hash)
    end

    def get_unspent_cells
      to = api.get_tip_number
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_redeem_script_hash(redeem_script_hash, current_from, current_to)
        results.concat(cells)
        current_from = current_to + 1
      end
      results
    end

    def get_balance
      get_unspent_cells.map { |c| c[:capacity] }.reduce(0, &:+)
    end

    def get_transaction(hash_hex)
      api.get_transaction(Ckb::Utils.hex_to_bin(hash_hex))
    end

    private
    def redeem_script_hash
      @__redeem_script_hash ||= api.calculate_redeem_script_hash(pubkey)
    end

    def self.random(api)
      self.new(api, SecureRandom.bytes(32))
    end

    def self.from_hex(api, privkey_hex)
      self.new(api, Ckb::Utils.hex_to_bin(privkey_hex))
    end
  end
end
