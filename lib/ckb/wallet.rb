require_relative "api"
require_relative "always_success_wallet"
require_relative "udt_wallet"
require_relative "utils"
require_relative "version"
require_relative "blake2b"

require "secp256k1"
require "securerandom"

module Ckb
  VERIFY_SCRIPT = File.read(File.expand_path("../../../scripts/secp256k1_blake2b_lock.rb", __FILE__))

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

    def lock
      verify_script_json_object
    end

    def get_unspent_cells
      to = api.get_tip_number
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_lock_hash(verify_script_hash, current_from, current_to)
        results.concat(cells)
        current_from = current_to + 1
      end
      results
    end

    def get_balance
      get_unspent_cells.map { |c| c[:capacity] }.reduce(0, &:+)
    end

    def generate_tx(target_lock, capacity)
      i = gather_inputs(capacity, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [
        {
          capacity: capacity,
          data: "",
          lock: target_lock
        }
      ]
      if input_capacities > capacity
        outputs << {
          capacity: input_capacities - capacity,
          data: "",
          lock: lock
        }
      end
      {
        version: 0,
        deps: [api.mruby_out_point],
        inputs: Ckb::Utils.sign_sighash_all_inputs(i.inputs, outputs, privkey),
        outputs: outputs
      }
    end

    def send_capacity(target_lock, capacity)
      tx = generate_tx(target_lock, capacity)
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
          data: "",
          lock: lock
        }
      end

      {
        version: 0,
        deps: [api.mruby_out_point],
        inputs: Ckb::Utils.sign_sighash_multiple_anyonecanpay_inputs(i.inputs, outputs, privkey),
        outputs: outputs
      }
    end

    # Create a new cell for storing an existing user defined token, you can
    # think this as an ethereum account for a user defined token
    def create_udt_account_wallet_cell(capacity, token_info)
      if udt_account_wallet(token_info).created?
        raise "Cell is already created!"
      end
      cell = {
        capacity: capacity,
        data: [0].pack("Q<"),
        lock: udt_account_wallet(token_info).lock,
        type: token_info.type_json_object
      }
      needed_capacity = Ckb::Utils.calculate_cell_min_capacity(cell)
      if capacity < needed_capacity
        raise "Not enough capacity for account cell, needed: #{needed_capacity}"
      end

      i = gather_inputs(capacity, MIN_UDT_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [cell]
      if input_capacities > capacity
        outputs << {
          capacity: input_capacities - capacity,
          data: "",
          lock: self.lock
        }
      end
      tx = {
        version: 0,
        deps: [api.mruby_out_point],
        inputs: Ckb::Utils.sign_sighash_all_inputs(i.inputs, outputs, privkey),
        outputs: outputs
      }
      hash = api.send_transaction(tx)
      # This is in fact an OutPoint here
      {
        hash: hash,
        index: 0
      }
    end

    # Create a user defined token with fixed upper amount, subsequent invocations
    # on this method will create different tokens.
    def create_fixed_amount_token(capacity, tokens, rate, lock: nil)
      lock ||= verify_script_json_object

      i = gather_inputs(capacity, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      ms = Ckb::Blake2b.new
      i.inputs.each do |input|
        ms.update(Ckb::Utils.hex_to_bin(input[:previous_output][:hash]))
        ms.update(input[:previous_output][:index].to_s)
      end

      info = FixedAmountTokenInfo.new(
        api,
        Ckb::Utils.bin_to_hex(ms.digest),
        lock,
        Ckb::Utils.bin_to_hex(pubkey_bin),
        rate)

      data = [tokens].pack("Q<")
      outputs = [
        {
          capacity: capacity,
          data: data,
          lock: info.genesis_lock_json_object,
          type: info.genesis_type_json_object
        }
      ]
      if input_capacities > capacity
        outputs << {
          capacity: input_capacities - capacity,
          data: "",
          lock: self.lock
        }
      end

      s = Ckb::Blake2b.new
      contract_hash_bin = Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_hash(outputs[0][:type]))
      s.update(contract_hash_bin)
      i.inputs.each do |input|
        s.update(Ckb::Utils.hex_to_bin(input[:previous_output][:hash]))
        s.update(input[:previous_output][:index].to_s)
      end
      s.update(outputs[0][:capacity].to_s)
      s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_hash(outputs[0][:lock])))
      s.update(contract_hash_bin)
      s.update(data)
      if outputs[1]
        s.update(outputs[1][:capacity].to_s)
        s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_hash(outputs[1][:lock])))
      end

      key = Secp256k1::PrivateKey.new(privkey: privkey)
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))

      outputs[0][:data] += signature

      tx = {
        version: 0,
        deps: [api.mruby_out_point],
        inputs: Ckb::Utils.sign_sighash_all_inputs(i.inputs, outputs, privkey),
        outputs: outputs
      }
      hash = api.send_transaction(tx)
      OpenStruct.new(tx_hash: hash, token_info: info)
    end

    def purchase_fixed_amount_token(tokens, token_info)
      paid_capacity = (tokens + token_info.rate - 1) / token_info.rate
      paid_cell = {
        capacity: paid_capacity,
        data: "",
        lock: token_info.issuer_lock
      }
      needed_capacity = Ckb::Utils.calculate_cell_min_capacity(paid_cell)
      if paid_capacity < needed_capacity
        raise "Not enough capacity for account cell, needed: #{needed_capacity}"
      end

      i = gather_inputs(paid_capacity, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      wallet_cell = udt_account_wallet(token_info).fetch_cell
      udt_genesis_cell = token_info.fetch_cell

      # Those won't require signing
      additional_inputs = [
        {
          previous_output: {
            hash: wallet_cell[:out_point][:hash],
            index: wallet_cell[:out_point][:index]
          },
          args: []
        },
        {
          previous_output: {
            hash: udt_genesis_cell[:out_point][:hash],
            index: udt_genesis_cell[:out_point][:index]
          },
          args: []
        }
      ]

      outputs = [
        {
          capacity: wallet_cell[:capacity],
          data: [wallet_cell[:amount] + tokens].pack("Q<"),
          lock: wallet_cell[:lock],
          type: token_info.type_json_object
        },
        {
          capacity: udt_genesis_cell[:capacity],
          data: [udt_genesis_cell[:amount] - tokens].pack("Q<"),
          lock: udt_genesis_cell[:lock],
          type: token_info.genesis_type_json_object
        },
        paid_cell
      ]
      if input_capacities > paid_capacity
        outputs << {
          capacity: input_capacities - paid_capacity,
          data: "",
          lock: self.lock
        }
      end

      signed_inputs = Ckb::Utils.sign_sighash_all_anyonecanpay_inputs(i.inputs, outputs, privkey)
      tx = {
        version: 0,
        deps: [api.mruby_out_point],
        inputs: signed_inputs + additional_inputs,
        outputs: outputs
      }
      api.send_transaction(tx)
    end

    # Issue a new user defined token using current wallet as token superuser
    def create_udt_token(capacity, token_name, tokens, account_wallet: false)
      token_info = created_token_info(token_name, account_wallet: account_wallet)
      wallet = account_wallet ? udt_account_wallet(token_info) : udt_wallet(token_info)

      data = [tokens].pack("Q<")
      s = Ckb::Blake2b.new
      s.update(data)
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))

      i = gather_inputs(capacity, MIN_UDT_CELL_CAPACITY)
      input_capacities = i.capacities

      udt_cell = {
        capacity: capacity,
        data: data + signature,
        lock: wallet.lock,
        type: token_info.type_json_object
      }
      min_capacity = Ckb::Utils.calculate_cell_min_capacity(udt_cell)
      if capacity < min_capacity
        raise "Capacity is not enough to hold the whole cell, minimal capacity: #{min_capacity}"
      end

      outputs = [udt_cell]
      if input_capacities > capacity
        outputs << {
          capacity: input_capacities - capacity,
          data: "",
          lock: self.lock
        }
      end
      tx = {
        version: 0,
        deps: [api.mruby_out_point],
        inputs: Ckb::Utils.sign_sighash_all_inputs(i.inputs, outputs, privkey),
        outputs: outputs
      }
      hash = api.send_transaction(tx)
      OpenStruct.new(tx_hash: hash, token_info: token_info)
    end

    def udt_wallet(token_info)
      Ckb::UdtWallet.new(api, privkey, token_info)
    end

    def udt_account_wallet(token_info)
      Ckb::UdtAccountWallet.new(api, privkey, token_info)
    end

    private
    def created_token_info(token_name, account_wallet: false)
      TokenInfo.new(api, token_name, Ckb::Utils.bin_to_hex(pubkey_bin), account_wallet)
    end

    def gather_inputs(capacity, min_capacity)
      if capacity < min_capacity
        raise "capacity cannot be less than #{min_capacity}"
      end

      input_capacities = 0
      inputs = []
      get_unspent_cells.each do |cell|
        input = {
          previous_output: {
            hash: cell[:out_point][:hash],
            index: cell[:out_point][:index]
          },
          args: [pubkey]
        }
        inputs << input
        input_capacities += cell[:capacity]
        if input_capacities >= capacity && (input_capacities - capacity) >= min_capacity
          break
        end
      end
      if input_capacities < capacity
        raise "Not enough capacity!"
      end
      OpenStruct.new(inputs: inputs, capacities: input_capacities)
    end

    def pubkey
      Ckb::Utils.bin_to_hex(pubkey_bin)
    end

    def pubkey_bin
      Ckb::Utils.extract_pubkey_bin(privkey)
    end

    def pubkey_hash_bin
      Ckb::Blake2b.digest(Ckb::Blake2b.digest(pubkey_bin))
    end

    def verify_script_json_object
      {
        version: 0,
        binary_hash: api.mruby_cell_hash,
        args: [
          # We could of course just hash raw bytes, but since right now CKB
          # CLI already uses this scheme, we stick to the same way for compatibility
          Ckb::Utils.bin_to_hex(pubkey_hash_bin)
        ]
      }
    end

    def verify_script_hash
      Ckb::Utils.json_script_to_hash(verify_script_json_object)
    end

    def self.random(api)
      self.new(api, SecureRandom.bytes(32))
    end

    def self.from_hex(api, privkey_hex)
      self.new(api, Ckb::Utils.hex_to_bin(privkey_hex))
    end
  end
end
