# frozen_string_literal: true

module Ckb
  module Udt
    class TokenInfo
      attr_reader :api
      attr_reader :name
      attr_reader :pubkey
      attr_reader :account_wallet

      # @param api [Ckb::Api]
      # @param name [String]
      # @param pubkey [String] "0x..."
      # @param account_wallet [Boolean]
      def initialize(api, name, pubkey, account_wallet)
        @api = api
        @name = name
        @pubkey = pubkey
        @account_wallet = account_wallet
      end

      # @param pubkey [String] "0x.."
      #
      # @return [Ckb::Script]
      def lock(pubkey)
        Script.new(
          binary_hash: api.mruby_cell_hash,
          args: [
            account_wallet ? UNLOCK_SINGLE_CELL_SCRIPT : UNLOCK_SCRIPT,
            name,
            pubkey
          ]
        )
      end

      # @return [Ckb::Script]
      def type
        Script.new(
          binary_hash: api.mruby_cell_hash,
          args: [
            CONTRACT_SCRIPT,
            name,
            pubkey
          ]
        )
      end

      def to_json(_opts)
        {
          name: name,
          pubkey: pubkey,
          account_wallet: account_wallet
        }.to_json
      end

      def self.from_json(api, json)
        o = JSON.parse(json, symbolize_names: true)
        TokenInfo.new(
          api,
          o[:name],
          o[:pubkey],
          o[:account_wallet]
        )
      end
    end
  end
end
