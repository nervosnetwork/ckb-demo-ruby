# frozen_string_literal: true

module Ckb
  module Udt
    class FixedAmountTokenInfo
      attr_reader :api
      attr_reader :input_hash
      attr_reader :issuer_lock
      attr_reader :pubkey
      attr_reader :rate

      # @param api [Ckb::Api]
      # @param input_hash [String]
      # @param issuer_lock [Ckb::Script]
      # @param pubkey [String] "0x.."
      # @param rate [Integer] exchange rate, N tokens per capacity
      def initialize(api, input_hash, issuer_lock, pubkey, rate)
        @api = api
        @input_hash = input_hash
        @issuer_lock = issuer_lock
        @pubkey = pubkey
        @rate = rate
      end

      def account_wallet
        true
      end

      # @return [Hash]
      def fetch_cell
        hash = genesis_lock.to_hash
        to = api.get_tip_number.to_i
        results = []
        current_from = 1
        while current_from <= to
          current_to = [current_from + 100, to].min
          cells = api.get_cells_by_lock_hash(hash, current_from.to_s, current_to.to_s)
          cells_with_data = cells.map do |cell|
            tx = api.get_transaction(cell[:out_point][:tx_hash])
            amount = Ckb::Utils.hex_to_bin(
              tx[:outputs][cell[:out_point][:index]][:data]
            ).unpack('Q<')[0]
            args = cell[:lock][:args].map do |arg|
              # arg.pack('c*')
              Ckb::Utils.hex_to_bin(arg)
            end
            lock = cell[:lock].merge(args: args)
            cell.merge(amount: amount, lock: lock)
          end
          results.concat(cells_with_data)
          current_from = current_to + 1
        end
        if results.length != 1
          raise "Invalid cell length: #{results.length}, something must be wrong here!"
        end

        results[0]
      end

      def genesis_lock
        Script.new(
          code_hash: api.mruby_cell_hash,
          args: [
            FIXED_AMOUNT_GENESIS_UNLOCK_SCRIPT,
            input_hash,
            rate.to_s,
            issuer_lock.to_hash,
            pubkey
          ]
        )
      end

      def genesis_type
        type
      end

      def lock(pubkey)
        Script.new(
          code_hash: api.mruby_cell_hash,
          args: [
            UNLOCK_SINGLE_CELL_SCRIPT,
            input_hash,
            pubkey
          ]
        )
      end

      def type
        Script.new(
          code_hash: api.mruby_cell_hash,
          args: [
            FIXED_AMOUNT_CONTRACT_SCRIPT,
            input_hash,
            pubkey
          ]
        )
      end

      def to_json(_opts)
        {
          input_hash: input_hash,
          issuer_lock: issuer_lock,
          pubkey: pubkey,
          rate: rate
        }.to_json
      end

      def self.from_json(api, json)
        o = JSON.parse(json, symbolize_names: true)
        FixedAmountTokenInfo.new(
          api,
          o[:input_hash],
          o[:issuer_lock],
          o[:pubkey],
          o[:rate]
        )
      end
    end
  end
end
