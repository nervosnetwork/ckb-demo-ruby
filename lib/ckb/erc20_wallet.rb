require_relative "api"
require_relative 'utils'

require "secp256k1"
require "securerandom"

module Ckb
  UNLOCK_SCRIPT = File.read(File.expand_path("../../../contracts/erc20/unlock.rb", __FILE__))
  CONTRACT_SCRIPT = File.read(File.expand_path("../../../contracts/erc20/contract.rb", __FILE__))

  class Erc20Wallet
    attr_reader :api
    attr_reader :privkey

    def initialize(api, privkey)
      unless privkey.instance_of?(String) && privkey.size == 32
        raise ArgumentError, "invalid privkey!"
      end

      @api = api
      @privkey = privkey
    end

    def address(coin_name)
      mruby_unlock_type_hash(coin_name)
    end

    def get_unspent_cells(coin_name)
      hash = mruby_unlock_type_hash(coin_name)
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

    def get_balance(coin_name)
      get_unspent_cells(coin_name).map { |c| c[:amount] }.reduce(0, &:+)
    end

    def send_amount(coin_name, erc20_address, amount)
    end

    def mruby_unlock_script_json_object(coin_name)
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          UNLOCK_SCRIPT,
          coin_name,
          # We could of course just hash raw bytes, but since right now CKB
          # CLI already uses this scheme, we stick to the same way for compatibility
          Ckb::Utils.bin_to_hex(pubkey_bin)
        ]
      }
    end

    def mruby_contract_script_json_object(coin_name)
      {
        version: 0,
        reference: api.mruby_cell_hash,
        signed_args: [
          CONTRACT_SCRIPT,
          coin_name,
          # We could of course just hash raw bytes, but since right now CKB
          # CLI already uses this scheme, we stick to the same way for compatibility
          Ckb::Utils.bin_to_hex(pubkey_bin)
        ]
      }
    end

    def mruby_unlock_type_hash(coin_name)
      Ckb::Utils.json_script_to_type_hash(mruby_unlock_script_json_object(coin_name))
    end

    def mruby_contract_type_hash(coin_name)
      Ckb::Utils.json_script_to_type_hash(mruby_contract_script_json_object(coin_name))
    end

    def get_transaction(hash_hex)
      api.get_transaction(hash_hex)
    end

    private
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
