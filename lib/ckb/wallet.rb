require_relative "api"
require_relative "udt_wallet"
require_relative "utils"

require "secp256k1"
require "securerandom"

module Ckb
  VERIFY_SCRIPT = File.read(File.expand_path("../../../contracts/bitcoin_unlock.rb", __FILE__))

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

    def generate_tx(target_address, capacity)
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
      {
        version: 0,
        deps: [api.mruby_script_outpoint],
        inputs: Ckb::Utils.sign_sighash_all_inputs(i.inputs, outputs, privkey),
        outputs: outputs
      }
    end

    def send_capacity(target_address, capacity)
      tx = generate_tx(target_address, capacity)
      api.send_transaction(tx)
    end

    def get_transaction(hash_hex)
      api.get_transaction(hash_hex)
    end

    def sign_capacity_for_udt_cell(capacity_to_pay, token_output)
      if capacity_to_pay < token_output[:capacity]
        raise "Not enough capacity paid!"
      end

      i = gather_inputs(capacity_to_pay, MIN_UDT_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [token_output]
      if input_capacities > capacity_to_pay
        outputs << {
          capacity: input_capacities - capacity_to_pay,
          data: [],
          lock: self.address
        }
      end

      {
        version: 0,
        deps: [api.mruby_script_outpoint],
        inputs: Ckb::Utils.sign_sighash_multiple_anyonecanpay_inputs(i.inputs, outputs, privkey),
        outputs: outputs
      }
    end

    def created_token_info(token_name)
      TokenInfo.new(token_name, Ckb::Utils.bin_to_hex(pubkey_bin))
    end

    def create_udt_token(capacity, token_name, tokens)
      token_info = created_token_info(token_name)

      i = gather_inputs(capacity, MIN_UDT_CELL_CAPACITY)
      input_capacities = i.capacities

      data = [tokens].pack("Q<")
      s = SHA3::Digest::SHA256.new
      s.update(Ckb::Utils.hex_to_bin(udt_wallet(token_info).mruby_contract_type_hash))
      s.update(data)
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
      signature_hex = Ckb::Utils.bin_to_hex(signature)

      outputs = [
        {
          capacity: capacity,
          data: data,
          lock: udt_wallet(token_info).address,
          contract: {
            version: 0,
            args: [
              signature_hex
            ],
            reference: api.mruby_cell_hash,
            signed_args: [
              Ckb::CONTRACT_SCRIPT,
              token_info.name,
              token_info.pubkey
            ]
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
        deps: [api.mruby_script_outpoint],
        inputs: Ckb::Utils.sign_sighash_all_inputs(i.inputs, outputs, privkey),
        outputs: outputs
      }
      hash = api.send_transaction(tx)
      OpenStruct.new(tx_hash: hash, token_info: token_info)
    end

    def udt_wallet(token_info)
      Ckb::UdtWallet.new(api, privkey, token_info)
    end

    private
    def gather_inputs(capacity, min_capacity)
      if capacity < min_capacity
        raise "capacity cannot be less than #{min_capacity}"
      end

      input_capacities = 0
      inputs = []
      get_unspent_cells.each do |cell|
        input = {
          previous_output: {
            hash: cell[:outpoint][:hash],
            index: cell[:outpoint][:index]
          },
          unlock: verify_script_json_object
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
      Ckb::Utils.extract_pubkey_bin(privkey)
    end

    def verify_script_json_object
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          VERIFY_SCRIPT,
          # We could of course just hash raw bytes, but since right now CKB
          # CLI already uses this scheme, we stick to the same way for compatibility
          Ckb::Utils.bin_to_hex(pubkey_bin)
        ]
      }
    end

    def verify_type_hash
      @__verify_type_hash ||= Ckb::Utils.json_script_to_type_hash(verify_script_json_object)
    end

    def self.random(api)
      self.new(api, SecureRandom.bytes(32))
    end

    def self.from_hex(api, privkey_hex)
      self.new(api, Ckb::Utils.hex_to_bin(privkey_hex))
    end
  end
end
