require_relative "api"
require_relative 'utils'

require "secp256k1"
require "securerandom"

module Ckb
  UNLOCK_SCRIPT = File.read(File.expand_path("../../../contracts/udt/unlock.rb", __FILE__))
  UNLOCK_SINGLE_CELL_SCRIPT = File.read(File.expand_path("../../../contracts/udt/unlock_single_cell.rb", __FILE__))
  CONTRACT_SCRIPT = File.read(File.expand_path("../../../contracts/udt/contract.rb", __FILE__))
  FIXED_AMOUNT_GENESIS_UNLOCK_SCRIPT = File.read(File.expand_path("../../../contracts/fixed_amount_udt/genesis_unlock.rb", __FILE__))
  FIXED_AMOUNT_CONTRACT_SCRIPT = File.read(File.expand_path("../../../contracts/fixed_amount_udt/contract.rb", __FILE__))

  class TokenInfo
    attr_reader :api
    attr_reader :name
    attr_reader :pubkey
    attr_reader :account_wallet

    def initialize(api, name, pubkey, account_wallet)
      @api = api
      @name = name
      @pubkey = pubkey
      @account_wallet = account_wallet
    end

    def unlock_script_json_object(pubkey)
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          account_wallet ? UNLOCK_SINGLE_CELL_SCRIPT : UNLOCK_SCRIPT,
          name,
          pubkey
        ],
        args: []
      }
    end

    def contract_script_json_object
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          CONTRACT_SCRIPT,
          name,
          pubkey
        ],
        args: []
      }
    end

    def to_json
      {
        api: api.uri.to_s,
        name: name,
        pubkey: pubkey,
        account_wallet: account_wallet
      }.to_json
    end

    def self.from_json(json)
      o = JSON.parse(json, symbolize_names: true)
      TokenInfo.new(Ckb::Api.new(host: o[:api]), o[:name], o[:pubkey], o[:account_wallet])
    end
  end

  class FixedAmountTokenInfo
    attr_reader :api
    attr_reader :input_hash
    attr_reader :lock_hash
    attr_reader :pubkey
    attr_reader :rate

    def initialize(api, input_hash, lock_hash, pubkey, rate)
      @api = api
      @input_hash = input_hash
      @lock_hash = lock_hash
      @pubkey = pubkey
      @rate = rate
    end

    def account_wallet
      true
    end

    def fetch_cell
      hash = genesis_unlock_type_hash
      to = api.get_tip_number
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_type_hash(hash, current_from, current_to)
        cells_with_data = cells.map do |cell|
          tx = api.get_transaction(cell[:out_point][:hash])
          amount = Ckb::Utils.hex_to_bin(tx[:transaction][:outputs][cell[:out_point][:index]][:data]).unpack("Q<")[0]
          cell.merge(amount: amount)
        end
        results.concat(cells_with_data)
        current_from = current_to + 1
      end
      if results.length != 1
        raise "Invalid cell length: #{results.length}, something must be wrong here!"
      end
      results[0]
    end

    def genesis_unlock_type_hash
      Ckb::Utils.json_script_to_type_hash(genesis_unlock_script_json_object)
    end

    def genesis_unlock_script_json_object
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          Ckb::FIXED_AMOUNT_GENESIS_UNLOCK_SCRIPT,
          rate.to_s,
          lock_hash,
          pubkey
        ],
        args: []
      }
    end

    def genesis_contract_script_json_object
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          Ckb::FIXED_AMOUNT_CONTRACT_SCRIPT,
          input_hash,
          pubkey
        ],
        args: []
      }
    end

    def unlock_script_json_object(pubkey)
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          UNLOCK_SINGLE_CELL_SCRIPT,
          input_hash,
          pubkey
        ],
        args: []
      }
    end

    def contract_script_json_object
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          Ckb::FIXED_AMOUNT_CONTRACT_SCRIPT,
          input_hash,
          pubkey
        ],
        args: []
      }
    end

    def to_json
      {
        api: api.uri.to_s,
        input_hash: input_hash,
        lock_hash: lock_hash,
        pubkey: pubkey,
        rate: rate
      }.to_json
    end

    def self.from_json(json)
      o = JSON.parse(json, symbolize_names: true)
      FixedAmountTokenInfo.new(Ckb::Api.new(host: o[:api]), o[:input_hash], o[:lock_hash], o[:pubkey], o[:rate])
    end
  end

  class UdtBaseWallet
    attr_reader :api
    attr_reader :privkey
    attr_reader :token_info

    def initialize(api, privkey, token_info)
      unless privkey.instance_of?(String) && privkey.size == 32
        raise ArgumentError, "invalid privkey!"
      end

      if !(token_info.instance_of?(TokenInfo) ||
           token_info.instance_of?(FixedAmountTokenInfo))
        raise ArgumentError, "invalid token info!"
      end

      @api = api
      @privkey = privkey
      @token_info = token_info
    end

    def wallet
      Ckb::Wallet.new(api, privkey)
    end

    def address
      unlock_type_hash
    end

    def unlock_type_hash
      Ckb::Utils.json_script_to_type_hash(token_info.unlock_script_json_object(pubkey))
    end

    def contract_type_hash
      Ckb::Utils.json_script_to_type_hash(token_info.contract_script_json_object)
    end

    def get_transaction(hash_hex)
      api.get_transaction(hash_hex)
    end

    def pubkey
      Ckb::Utils.bin_to_hex(pubkey_bin)
    end

    def pubkey_bin
      Ckb::Utils.extract_pubkey_bin(privkey)
    end

    def get_unspent_cells
      hash = unlock_type_hash
      to = api.get_tip_number
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_type_hash(hash, current_from, current_to)
        cells_with_data = cells.select do |cell|
          cell[:lock] == address
        end.map do |cell|
          tx = get_transaction(cell[:out_point][:hash])
          amount = Ckb::Utils.hex_to_bin(tx[:transaction][:outputs][cell[:out_point][:index]][:data]).unpack("Q<")[0]
          cell.merge(amount: amount)
        end
        results.concat(cells_with_data)
        current_from = current_to + 1
      end
      results
    end
  end

  class UdtWallet < UdtBaseWallet
    def get_balance
      get_unspent_cells.map { |c| c[:amount] }.reduce(0, &:+)
    end

    # Generate a partial tx which provides CKB coins in exchange for UDT tokens.
    # UDT sender should use +send_amount+ to fill in the other part
    def generate_partial_tx_for_udt_cell(token_amount, udt_cell_capacity, exchange_capacity)
      output = generate_output(address, token_amount, udt_cell_capacity)
      wallet.sign_capacity_for_udt_cell(udt_cell_capacity + exchange_capacity, output)
    end

    def send_amount(amount, partial_tx)
      outputs = partial_tx[:outputs]
      inputs = partial_tx[:inputs].map do |input|
        args = input[:unlock][:args] + [outputs.length.times.to_a.join(",")]
        unlock = input[:unlock].merge(args: args)
        input.merge(unlock: unlock)
      end

      i = gather_inputs(amount)

      input_capacities = inputs.map do |input|
        api.get_live_cell(input[:previous_output])[:cell][:capacity]
      end.reduce(&:+)
      output_capacities = outputs.map do |output|
        output[:capacity]
      end.reduce(&:+)

      # If there's more input capacities than output capacities, collect them
      spare_cell_capacity = input_capacities - output_capacities
      if i.amounts > amount
        outputs << {
          capacity: i.capacities,
          data: [i.amounts - amount].pack("Q<"),
          lock: address,
          type: token_info.contract_script_json_object
        }
        if spare_cell_capacity > MIN_CELL_CAPACITY
          outputs << {
            capacity: spare_cell_capacity,
            data: "",
            lock: wallet.address
          }
        end
      else
        outputs << {
          capacity: i.capacities + spare_cell_capacity,
          data: "",
          lock: wallet.address
        }
      end

      self_inputs = Ckb::Utils.sign_sighash_all_anyonecanpay_inputs(i.inputs, outputs, privkey)
      tx = {
        version: 0,
        deps: [api.mruby_out_point],
        inputs: inputs + self_inputs,
        outputs: outputs
      }
      api.send_transaction(tx)
    end

    # Merge multiple UDT cells into one so we can use UdtAccountWallet
    def merge_cells
      inputs = []
      total_amount = 0
      total_capacity = 0
      get_unspent_cells.each do |cell|
        input = {
          previous_output: {
            hash: cell[:out_point][:hash],
            index: cell[:out_point][:index]
          },
          unlock: token_info.unlock_script_json_object(pubkey)
        }
        inputs << input
        input_capacity += cell[:capacity]
        input_amount += cell[:amount]
      end
      outputs = [
        {
          capacity: total_capacity,
          data: [total_amount].pack("Q<"),
          lock: wallet.udt_cell_wallet(token_info).address,
          type: token_info.contract_script_json_object
        }
      ]
      tx = {
        version: 0,
        deps: [api.mruby_out_point],
        inputs: Ckb::Utils.sign_sighash_all_inputs(inputs, outputs, privkey),
        outputs: outputs
      }
      api.send_transaction(tx)
    end

    private
    def generate_output(udt_address, amount, capacity)
      output = {
        capacity: capacity,
        data: [amount].pack("Q<"),
        lock: udt_address,
        type: token_info.contract_script_json_object
      }

      min_capacity = Ckb::Utils.calculate_cell_min_capacity(output)
      if capacity < min_capacity
        raise "Capacity is not enough to hold the whole cell, minimal capacity: #{min_capacity}"
      end

      output
    end

    def gather_inputs(amount)
      input_capacities = 0
      input_amounts = 0
      inputs = []
      get_unspent_cells.each do |cell|
        input = {
          previous_output: {
            hash: cell[:out_point][:hash],
            index: cell[:out_point][:index]
          },
          unlock: token_info.unlock_script_json_object(pubkey)
        }
        inputs << input
        input_capacities += cell[:capacity]
        input_amounts += cell[:amount]
        if input_amounts >= amount
          break
        end
      end
      if input_amounts < amount
        raise "Not enough amount!"
      end
      OpenStruct.new(inputs: inputs, amounts: input_amounts,
                     capacities: input_capacities)
    end
  end

  class UdtAccountWallet < UdtBaseWallet
    def get_balance
      fetch_cell[:amount]
    end

    def latest_out_point
      fetch_cell[:out_point]
    end

    def created?
      get_unspent_cells.length > 0
    end

    def fetch_cell
      cells = get_unspent_cells
      case cells.length
      when 0
        raise "Please create udt cell wallet first!"
      when 1
        cells[0]
      else
        raise "There's more than one cell for this UDT! You can use merge_cells in UdtWallet to merge them into one"
      end
    end

    # Generates a partial tx that provides some UDTs for other user, who
    # can only accept the exact amount provided here but no more
    def send_tokens(amount, target_wallet)
      cell = fetch_cell
      target_cell = target_wallet.fetch_cell
      if amount > cell[:amount]
        raise "Do not have that much amount!"
      end
      inputs = [
        {
          previous_output: {
            hash: cell[:out_point][:hash],
            index: cell[:out_point][:index]
          },
          unlock: token_info.unlock_script_json_object(pubkey)
        }
      ]
      outputs = [
        {
          capacity: cell[:capacity],
          data: [cell[:amount] - amount].pack("Q<"),
          lock: address,
          type: token_info.contract_script_json_object
        },
        {
          capacity: target_cell[:capacity],
          data: [target_cell[:amount] + amount].pack("Q<"),
          lock: target_cell[:lock],
          type: token_info.contract_script_json_object
        }
      ]
      signed_inputs = Ckb::Utils.sign_sighash_all_anyonecanpay_inputs(inputs, outputs, privkey)
      # This doesn't need a signature
      target_input = {
        previous_output: {
          hash: target_cell[:out_point][:hash],
          index: target_cell[:out_point][:index]
        },
        unlock: target_wallet.token_info.unlock_script_json_object(target_wallet.pubkey),
      }
      tx = {
        version: 0,
        deps: [api.mruby_out_point],
        inputs: signed_inputs + [target_input],
        outputs: outputs
      }
      api.send_transaction(tx)
    end
  end
end
