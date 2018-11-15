require_relative "api"
require_relative "erc20_wallet"
require_relative "utils"

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

    def address
      verify_type_hash
    end

    def get_unspent_cells
      to = api.get_tip_number
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_type_hash(verify_type_hash, current_from, current_to)
        results.concat(cells)
        current_from = current_to + 1
      end
      results
    end

    def get_balance
      get_unspent_cells.map { |c| c[:capacity] }.reduce(0, &:+)
    end

    def send_capacity(target_address, capacity)
      i = gather_inputs(capacity, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [
        {
          capacity: capacity,
          data: [],
          lock: target_address
        }
      ]
      if input_capacities > capacity
        outputs << {
          capacity: input_capacities - capacity,
          data: [],
          lock: self.address
        }
      end
      tx = {
        version: 0,
        deps: [
          {
            hash: Ckb::Utils.bin_to_prefix_hex(api.basic_verify_script_outpoint.hash_value),
            index: api.basic_verify_script_outpoint.index
          }
        ],
        inputs: i.inputs,
        outputs: outputs
      }
      api.send_transaction(tx)
    end

    def get_transaction(hash_hex)
      api.get_transaction(hash_hex)
    end

    def create_erc20_cell(capacity, coin_name, coins)
      i = gather_inputs(capacity, MIN_ERC20_CELL_CAPACITY)
      input_capacities = i.capacities

      data = [coins].pack("Q<")
      s = SHA3::Digest::SHA256.new
      s.update(Ckb::Utils.hex_to_bin(erc20_wallet.mruby_contract_type_hash(coin_name)))
      s.update(data)
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
      signature_hex = Ckb::Utils.bin_to_hex(signature)

      outputs = [
        {
          capacity: capacity,
          data: data.bytes.to_a,
          lock: erc20_wallet.address(coin_name),
          contract: {
            version: 0,
            args: [
              erc20_wallet.mruby_contract_type_hash(coin_name),
              signature_hex
            ].map { |a| a.bytes.to_a },
            reference: Ckb::Utils.bin_to_prefix_hex(api.mruby_cell_hash),
            signed_args: [
              Ckb::CONTRACT_SCRIPT,
              coin_name,
              Ckb::Utils.bin_to_hex(pubkey_bin)
            ].map { |a| a.bytes.to_a }
          }
        }
      ]
      if input_capacities > capacity
        outputs << {
          capacity: input_capacities - capacity,
          data: [],
          lock: self.address
        }
      end
      tx = {
        version: 0,
        deps: [
          {
            hash: Ckb::Utils.bin_to_prefix_hex(api.basic_verify_script_outpoint.hash_value),
            index: api.basic_verify_script_outpoint.index
          },
          {
            hash: Ckb::Utils.bin_to_prefix_hex(api.mruby_script_outpoint.hash_value),
            index: api.mruby_script_outpoint.index
          }
        ],
        inputs: i.inputs,
        outputs: outputs
      }
      api.send_transaction(tx)
    end

    def erc20_wallet
      Ckb::Erc20Wallet.new(api, privkey)
    end

    private
    def gather_inputs(capacity, min_capacity)
      if capacity < min_capacity
        raise "capacity cannot be less than #{min_capacity}"
      end

      key = Secp256k1::PrivateKey.new(privkey: privkey)
      input_capacities = 0
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
              Ckb::Utils.bin_to_hex(pubkey_bin)
            ].map { |a| a.bytes.to_a }
          }
        }
        inputs << input
        input_capacities += cell[:capacity]
        if input_capacities >= capacity && (input_capacities - capacity) >= min_capacity
          break
        end
      end
      if input_capacities < capacity
        raise "Not enouch capacity!"
      end
      OpenStruct.new(inputs: inputs, capacities: input_capacities)
    end

    def pubkey_bin
      Ckb::Utils.extract_pubkey(privkey)
    end

    def verify_type_hash
      @__verify_type_hash ||=
        begin
          s = SHA3::Digest::SHA256.new
          s << api.verify_cell_hash
          s << "|"
          # We could of course just hash raw bytes, but since right now CKB
          # CLI already uses this scheme, we stick to the same way for compatibility
          s << Ckb::Utils.bin_to_hex(pubkey_bin)
          Ckb::Utils.bin_to_prefix_hex(s.digest)
        end
    end

    def self.random(api)
      self.new(api, SecureRandom.bytes(32))
    end

    def self.from_hex(api, privkey_hex)
      self.new(api, Ckb::Utils.hex_to_bin(privkey_hex))
    end
  end
end
