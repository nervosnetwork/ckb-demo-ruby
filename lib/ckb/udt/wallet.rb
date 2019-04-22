# frozen_string_literal: true

require_relative 'base_wallet'

module Ckb
  module Udt
    class Wallet < BaseWallet
      def get_balance
        get_unspent_cells.map { |c| c[:amount].to_i }.reduce(0, &:+)
      end

      # Generate a partial tx which provides CKB coins in exchange for UDT tokens.
      # UDT sender should use +send_amount+ to fill in the other part
      def generate_partial_tx_for_udt_cell(token_amount, udt_cell_capacity, exchange_capacity)
        output = generate_output(lock, token_amount, udt_cell_capacity)
        wallet.sign_capacity_for_udt_cell(udt_cell_capacity + exchange_capacity, output)
      end

      # @param amount [Integer]
      # @param partial_tx [Ckb::Transaction]
      def send_amount(amount, partial_tx)
        outputs = partial_tx.outputs

        inputs = partial_tx.inputs.map do |input|
          input.args += [outputs.length.times.to_a.join(',')]
          input
        end

        i = gather_inputs(amount)

        input_capacities = inputs.map do |input|
          api.get_live_cell(input.previous_output.to_h)[:cell][:capacity].to_i
        end.reduce(0, &:+)
        output_capacities = outputs.map do |output|
          output.capacity.to_i
        end.reduce(0, &:+)

        # If there's more input capacities than output capacities, collect them
        spare_cell_capacity = input_capacities - output_capacities
        if i.amounts > amount
          outputs << Output.new(
            capacity: i.capacities.to_s,
            data: [i.amounts - amount].pack('Q<'),
            lock: lock,
            type: token_info.type
          )
          if spare_cell_capacity > MIN_CELL_CAPACITY
            outputs << Output.new(
              capacity: spare_cell_capacity.to_s,
              data: '0x',
              lock: wallet.lock
            )
          end
        else
          outputs << Output.new(
            capacity: (i.capacities + spare_cell_capacity).to_s,
            data: '0x',
            lock: wallet.lock
          )
        end

        self_inputs = Ckb::Transaction.sign_sighash_all_anyonecanpay_inputs(i.inputs, outputs, @key.privkey)

        tx = Transaction.new(
          version: 0,
          deps: [api.mruby_out_point],
          inputs: inputs + self_inputs,
          outputs: outputs,
          witnesses: []
        )
        api.send_transaction(tx)
      end

      # Merge multiple UDT cells into one so we can use Udt::AccountWallet
      def merge_cells
        inputs = []
        total_amount = 0
        total_capacity = 0
        get_unspent_cells.each do |cell|
          input = Input.new(
            previous_output: OutPoint.new(
              hash: cell[:out_point][:hash],
              index: cell[:out_point][:index]
            ),
            lock: token_info.lock(pubkey),
            valid_since: '0'
          )
          inputs << input
          total_capacity += cell[:capacity].to_i
          total_amount += cell[:amount]
        end
        outputs = [
          Output.new(
            capacity: total_capacity.to_s,
            data: [total_amount].pack('Q<'),
            lock: wallet.udt_cell_wallet(token_info).address,
            type: token_info.type
          )
        ]
        tx = Transaction.new(
          version: 0,
          deps: [api.mruby_out_point],
          inputs: inputs,
          outputs: outputs,
          witnesses: []
        ).sign_sighash_all_inputs(@key.privkey)
        api.send_transaction(tx)
      end

      private

      # @param udt_lock [Script]
      # @param amount [Integer]
      # @param capacity [Integer]
      #
      # @return [Output]
      def generate_output(udt_lock, amount, capacity)
        output = Output.new(
          capacity: capacity,
          data: [amount].pack('Q<'),
          lock: udt_lock,
          type: token_info.type
        )

        min_capacity = output.calculate_min_capacity
        if capacity < min_capacity
          raise "Capacity is not enough to hold the whole cell, minimal capacity: #{min_capacity}"
        end

        output
      end

      # @param amount [Integer]
      def gather_inputs(amount)
        input_capacities = 0
        input_amounts = 0
        inputs = []
        get_unspent_cells.each do |cell|
          input = Input.new(
            previous_output: OutPoint.new(
              hash: cell[:out_point][:hash],
              index: cell[:out_point][:index]
            ),
            args: [],
            valid_since: '0'
          )
          inputs << input
          input_capacities += cell[:capacity].to_i
          input_amounts += cell[:amount].to_i
          break if input_amounts >= amount
        end
        raise 'Not enough amount!' if input_amounts < amount

        OpenStruct.new(
          inputs: inputs,
          amounts: input_amounts,
          capacities: input_capacities
        )
      end
    end
  end
end
