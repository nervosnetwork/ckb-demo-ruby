require_relative "api"
require_relative 'utils'

require "secp256k1"
require "securerandom"

module Ckb
  UNLOCK_SCRIPT = File.read(File.expand_path("../../../contracts/udt/unlock.rb", __FILE__))
  CONTRACT_SCRIPT = File.read(File.expand_path("../../../contracts/udt/contract.rb", __FILE__))

  class CoinInfo
    attr_reader :name
    attr_reader :pubkey

    def initialize(name, pubkey)
      @name = name
      @pubkey = pubkey
    end
  end

  class UdtWallet
    attr_reader :api
    attr_reader :privkey
    attr_reader :coin_info

    def initialize(api, privkey, coin_info)
      unless privkey.instance_of?(String) && privkey.size == 32
        raise ArgumentError, "invalid privkey!"
      end

      unless coin_info.instance_of?(CoinInfo)
        raise ArgumentError, "invalid coin info!"
      end

      @api = api
      @privkey = privkey
      @coin_info = coin_info
    end

    def wallet
      Ckb::Wallet.new(api, privkey)
    end

    def address
      mruby_unlock_type_hash
    end

    def get_unspent_cells
      hash = mruby_unlock_type_hash
      to = api.get_tip_number
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_type_hash(hash, current_from, current_to)
        cells_with_data = cells.map do |cell|
          tx = get_transaction(cell[:outpoint][:hash])
          amount = tx[:transaction][:outputs][cell[:outpoint][:index]][:data].pack("c*").unpack("Q<")[0]
          cell.merge(amount: amount)
        end
        results.concat(cells_with_data)
        current_from = current_to + 1
      end
      results
    end

    def get_balance
      get_unspent_cells.map { |c| c[:amount] }.reduce(0, &:+)
    end

    def generate_output(udt_address, amount, capacity)
      output = {
        capacity: capacity,
        data: [amount].pack("Q<"),
        lock: udt_address,
        contract: {
          version: 0,
          args: [
            mruby_contract_type_hash
          ],
          reference: api.mruby_cell_hash,
          signed_args: [
            Ckb::CONTRACT_SCRIPT,
            coin_info.name,
            coin_info.pubkey
          ]
        }
      }

      min_capacity = calculate_cell_min_capacity(output)
      if capacity < min_capacity
        raise "Capacity is not enough to hold the whole cell, minimal capacity: #{min_capacity}"
      end

      output
    end

    def send_amount(amount, inputs, outputs)
      i = gather_inputs(amount)

      if i.amounts > amount
        outputs << {
          capacity: i.capacities,
          data: [i.amounts - amount].pack("Q<"),
          lock: address,
          contract: {
            version: 0,
            args: [mruby_contract_type_hash],
            reference: api.mruby_cell_hash,
            signed_args: [
              Ckb::CONTRACT_SCRIPT,
              coin_info.name,
              coin_info.pubkey
            ]
          }
        }
      else
        outputs << {
          capacity: i.capacities,
          data: [],
          lock: wallet.address
        }
      end

      start = inputs.size
      length = i.inputs.size

      tx = {
        version: 0,
        deps: [api.mruby_script_outpoint],
        inputs: sign_inputs(inputs.concat(i.inputs), outputs,
                            start: start, length: length),
        outputs: outputs
      }
      api.send_transaction(tx)
    end

    def mruby_unlock_script_json_object
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          UNLOCK_SCRIPT,
          coin_info.name,
          Ckb::Utils.bin_to_hex(pubkey_bin)
        ]
      }
    end

    def mruby_contract_script_json_object
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          CONTRACT_SCRIPT,
          coin_info.name,
          coin_info.pubkey
        ]
      }
    end

    def mruby_unlock_type_hash
      Ckb::Utils.json_script_to_type_hash(mruby_unlock_script_json_object)
    end

    def mruby_contract_type_hash
      Ckb::Utils.json_script_to_type_hash(mruby_contract_script_json_object)
    end

    def get_transaction(hash_hex)
      api.get_transaction(hash_hex)
    end

    private
    def calculate_cell_min_capacity(output)
      capacity = 8 + output[:data].size + Ckb::Utils.hex_to_bin(output[:lock]).size
      if contract = output[:contract]
        capacity += 1
        capacity += (contract[:args] || []).map { |arg| arg.size }.reduce(&:+)
        if contract[:reference]
          capacity += Ckb::Utils.hex_to_bin(contract[:reference]).size
        end
        if contract[:binary]
          capacity += contract[:binary].size
        end
        capacity += (contract[:signed_args] || []).map { |arg| arg.size }.reduce(&:+)
      end
      capacity
    end

    def sign_inputs(inputs, outputs, start: 0, length: nil)
      length ||= inputs.size
      hash_indices = "#{inputs.size.times.to_a.join(",")}|#{outputs.size.times.to_a.join(",")}|"
      s = SHA3::Digest::SHA256.new
      s.update(hash_indices)
      inputs.each do |input|
        s.update(Ckb::Utils.hex_to_bin(input[:previous_output][:hash]))
        s.update(input[:previous_output][:index].to_s)
        s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(input[:unlock])))
      end
      outputs.each do |output|
        s.update(output[:capacity].to_s)
        s.update(Ckb::Utils.hex_to_bin(output[:lock]))
        if output[:contract]
          s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(output[:contract])))
        end
      end
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
      signature_hex = Ckb::Utils.bin_to_hex(signature)

      for i in start...start+length do
        input = inputs[i]
        input[:unlock][:args] = [signature_hex, hash_indices]
      end

      inputs
    end

    def gather_inputs(amount)
      input_capacities = 0
      input_amounts = 0
      inputs = []
      get_unspent_cells.each do |cell|
        input = {
          previous_output: {
            hash: cell[:outpoint][:hash],
            index: cell[:outpoint][:index]
          },
          unlock: mruby_unlock_script_json_object
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

    def pubkey_bin
      Ckb::Utils.extract_pubkey_bin(privkey)
    end

    def self.random(api)
      self.new(api, SecureRandom.bytes(32))
    end

    def self.from_hex(api, privkey_hex)
      self.new(api, Ckb::Utils.hex_to_bin(privkey_hex))
    end
  end
end
