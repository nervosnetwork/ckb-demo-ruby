require_relative 'api'
require_relative 'utils'
require_relative 'blake2b'

module Ckb
  class AlwaysSuccessWallet
    attr_reader :api

    def initialize(api)
      @api = api
    end

    # @param target_lock [Ckb::Script]
    # @param capacity [Integer]
    def send_capacity(target_lock, capacity)
      i = gather_inputs(capacity, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [
        Output.new(
          capacity: capacity.to_s,
          lock: target_lock
        )
      ]

      if input_capacities > capacity
        outputs << Output.new(
          capacity: (input_capacities - capacity).to_s,
          lock: lock_script
        )
      end

      tx = Transaction.new(
        version: 0,
        deps: [],
        inputs: i.inputs,
        outputs: outputs
      )
      api.send_transaction(tx)
    end

    def install_mruby_cell!(mruby_cell_filename)
      data = File.read(mruby_cell_filename)
      cell_hash = Ckb::Utils.bin_to_hex(Ckb::Blake2b.digest(data))
      output = Output.new(
        capacity: 0,
        data: data,
        lock: lock_script
      )
      output.capacity = output.calculate_min_capacity.to_s

      i = gather_inputs(output.capacity.to_i, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [output]
      if input_capacities > output.capacity.to_i
        outputs << Output.new(
          capacity: (input_capacities - output.capacity.to_i).to_s,
          lock: lock_script
        )
      end

      tx = Transaction.new(
        version: 0,
        deps: [],
        inputs: i.inputs,
        outputs: outputs
      )
      hash = api.send_transaction(tx)
      {
        out_point: {
          hash: hash,
          index: 0
        },
        cell_hash: cell_hash
      }
    end

    def configuration_installed?(configuration)
      cell_with_status = api.get_live_cell(configuration[:out_point])
      return false if cell_with_status[:status] != 'live'

      returned_cell_hash = Ckb::Utils.bin_to_hex(
        Ckb::Blake2b.digest(
          Ckb::Utils.hex_to_bin(
            cell_with_status[:cell][:data]
          )
        )
      )
      unless returned_cell_hash == configuration[:cell_hash]
        raise "Cell hash doesn't match, something weird is happening!"
      end

      true
    end

    def get_balance
      get_unspent_cells.map { |c| c[:capacity].to_i }.reduce(0, &:+)
    end

    private

    def lock_hash
      @__lock_hash ||= lock_script.to_hash
    end

    def lock_script
      Script.new(
        binary_hash: '0x0000000000000000000000000000000000000000000000000000000000000001',
        args: []
      )
    end

    def get_unspent_cells
      to = api.get_tip_number.to_i
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_lock_hash(lock_hash, current_from.to_s, current_to.to_s)
        results.concat(cells)
        current_from = current_to + 1
      end
      results
    end

    def gather_inputs(capacity, min_capacity)
      if capacity < min_capacity
        raise "capacity cannot be less than #{min_capacity}"
      end

      input_capacities = 0
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
        if input_capacities >= capacity && (input_capacities - capacity) >= min_capacity
          break
        end
      end
      if input_capacities < capacity
        raise "Not enough capacity, required: #{capacity}, available: #{input_capacities}"
      end

      OpenStruct.new(inputs: inputs, capacities: input_capacities)
    end
  end
end
