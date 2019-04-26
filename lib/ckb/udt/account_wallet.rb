# frozen_string_literal: true

require_relative 'base_wallet'
require 'pry'

module Ckb
  module Udt
    class AccountWallet < BaseWallet
      def get_balance
        fetch_cell[:amount]
      end

      def latest_out_point
        fetch_cell[:out_point]
      end

      def created?
        !get_unspent_cells.empty?
      end

      # @return [Hash]
      def fetch_cell
        cells = get_unspent_cells
        case cells.length
        when 0
          raise 'Please create udt cell wallet first!'
        when 1
          cell = cells[0]
          args = cell[:lock][:args].map do |arg|
            Ckb::Utils.hex_to_bin(arg)
          end
          lock = cell[:lock].merge(args: args)
          cell.merge(lock: lock)
        else
          raise "There's more than one cell for this UDT! You can use merge_cells in Udt::Wallet to merge them into one"
        end
      end

      # Generates a partial tx that provides some UDTs for other user, who
      # can only accept the exact amount provided here but no more
      #
      # @param amount [Integer]
      def send_tokens(amount, target_wallet)
        cell = fetch_cell
        target_cell = target_wallet.fetch_cell
        raise 'Do not have that much amount!' if amount > cell[:amount]

        inputs = [
          Input.new(
            previous_output: OutPoint.new(
              tx_hash: cell[:out_point][:tx_hash],
              index: cell[:out_point][:index]
            ),
            args: [],
            since: '0'
          )
        ]
        outputs = [
          Output.new(
            capacity: cell[:capacity].to_s,
            data: [cell[:amount] - amount].pack('Q<'),
            lock: lock,
            type: token_info.type
          ),
          Output.new(
            capacity: target_cell[:capacity].to_s,
            data: [target_cell[:amount] + amount].pack('Q<'),
            lock: Script.from_h(target_cell[:lock]),
            type: token_info.type
          )
        ]
        signed_inputs = Ckb::Transaction.sign_sighash_all_anyonecanpay_inputs(inputs, outputs, @key.privkey)
        # This doesn't need a signature
        target_input = Input.new(
          previous_output: OutPoint.new(
            tx_hash: target_cell[:out_point][:tx_hash],
            index: target_cell[:out_point][:index]
          ),
          args: [],
          since: '0'
        )

        tx = Transaction.new(
          version: 0,
          deps: [api.mruby_out_point],
          inputs: signed_inputs + [target_input],
          outputs: outputs
        )
        api.send_transaction(tx)
      end
    end
  end
end
