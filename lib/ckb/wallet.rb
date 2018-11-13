require_relative "api"
require_relative 'utils'

require "secp256k1"
require "securerandom"

module Ckb
  MIN_CELL_CAPACITY = 40

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
      Ckb::Utils.bin_to_prefix_hex(type_hash)
    end

    def get_unspent_cells
      to = api.get_tip_number
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_type_hash(type_hash, current_from, current_to)
        results.concat(cells)
        current_from = current_to + 1
      end
      results
    end

    def get_balance
      get_unspent_cells.map { |c| c[:capacity] }.reduce(0, &:+)
    end

    def send_amount(target_address, amount)
      if amount < MIN_CELL_CAPACITY
        raise "amount cannot be less than #{MIN_CELL_CAPACITY}"
      end

      key = Secp256k1::PrivateKey.new(privkey: privkey)
      input_amounts = 0
      inputs = []
      get_unspent_cells.each do |cell|
        arguments = ["signingmessage"]
        hash1 = SHA3::Digest::SHA256.digest(arguments.join)
        hash2 = SHA3::Digest::SHA256.digest(hash1)
        signature = key.ecdsa_serialize(key.ecdsa_sign(hash2, raw: true))
        signature_hex = Ckb::Utils.bin_to_hex(signature)
        arguments.unshift(signature_hex)
        input = {
          previous_output: {
            hash: cell[:outpoint][:hash],
            index: cell[:outpoint][:index]
          },
          unlock: {
            version: 0,
            args: arguments.map { |a| a.bytes.to_a },
            reference: Ckb::Utils.bin_to_prefix_hex(api.verify_cell_hash),
            signed_args: [
              Ckb::Utils.bin_to_hex(pubkey)
            ].map { |a| a.bytes.to_a }
          }
        }
        inputs << input
        input_amounts += cell[:capacity]
        if input_amounts >= amount && (input_amounts - amount) >= MIN_CELL_CAPACITY
          break
        end
      end
      outputs = [
        {
          capacity: amount,
          data: [],
          lock: target_address
        }
      ]
      if input_amounts > amount
        outputs << {
          capacity: input_amounts - amount,
          data: [],
          lock: self.address
        }
      end
      tx = {
        version: 0,
        deps: [
          {
            hash: Ckb::Utils.bin_to_prefix_hex(api.get_system_redeem_script_outpoint.hash_value),
            index: api.get_system_redeem_script_outpoint.index
          }
        ],
        inputs: inputs,
        outputs: outputs
      }
      api.send_transaction(tx)
    end

    def get_transaction(hash_hex)
      api.get_transaction(Ckb::Utils.hex_to_bin(hash_hex))
    end

    private
    def type_hash
      @__type_hash ||= api.calculate_type_hash(pubkey)
    end

    def self.random(api)
      self.new(api, SecureRandom.bytes(32))
    end

    def self.from_hex(api, privkey_hex)
      self.new(api, Ckb::Utils.hex_to_bin(privkey_hex))
    end
  end
end
