# frozen_string_literal: true

module Ckb
  module Udt
    class BaseWallet
      attr_reader :api
      attr_reader :key
      attr_reader :token_info

      # @param api [Ckb::Api]
      # @param privkey [String] "0x..."
      # @param token_info [Udt::TokenInfo | Udt::FixedAmountTokenInfo]
      def initialize(api, privkey, token_info)
        @key = Ckb::Key.new(privkey)

        unless token_info.instance_of?(TokenInfo) ||
               token_info.instance_of?(FixedAmountTokenInfo)
          raise ArgumentError, 'invalid token info!'
        end

        @api = api
        @token_info = token_info
      end

      def wallet
        Ckb::Wallet.new(api, @key)
      end

      def lock
        token_info.lock(@key.pubkey)
      end

      def lock_hash
        token_info.lock(@key.pubkey).to_hash
      end

      def get_transaction(hash)
        api.get_transaction(hash)
      end

      def get_unspent_cells
        hash = lock_hash
        to = api.get_tip_number.to_i
        results = []
        current_from = 1
        while current_from <= to
          current_to = [current_from + 100, to].min
          cells = api.get_cells_by_lock_hash(hash, current_from.to_s, current_to.to_s)
          cells_with_data = cells.map do |cell|
            tx = get_transaction(cell[:out_point][:tx_hash])[:transaction]
            amount = Ckb::Utils.hex_to_bin(
              tx[:outputs][cell[:out_point][:index]][:data]
            ).unpack('Q<')[0]
            cell.merge(amount: amount)
          end
          results.concat(cells_with_data)
          current_from = current_to + 1
        end
        results
      end
    end
  end
end
