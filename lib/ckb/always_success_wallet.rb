require_relative "api"
require_relative "utils"
require_relative "blake2b"

module Ckb
  class AlwaysSuccessWallet
    attr_reader :api

    def initialize(api)
      @api = api
    end

    def send_capacity(target_lock, capacity)
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
          lock: lock_script_json_object
        }
      end
      tx = {
        version: 0,
        deps: [api.always_success_out_point],
        inputs: i.inputs,
        outputs: outputs,
        embeds: []
      }
      api.send_transaction(tx)
    end

    def install_mruby_cell!(mruby_cell_filename)
      data = File.read(mruby_cell_filename)
      cell_hash = Ckb::Utils.bin_to_prefix_hex(Ckb::Blake2b.digest(data))
      output = {
        capacity: 0,
        data: data,
        lock: lock_script_json_object
      }
      output[:capacity] = Ckb::Utils.calculate_cell_min_capacity(output)

      i = gather_inputs(output[:capacity], MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [output]
      if input_capacities > output[:capacity]
        outputs << {
          capacity: input_capacities - output[:capacity],
          data: "",
          lock: lock_script_json_object
        }
      end

      tx = {
        version: 0,
        deps: [api.always_success_out_point],
        inputs: i.inputs,
        outputs: outputs,
        embeds: []
      }
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
      return false if cell_with_status[:status] != "live"
      returned_cell_hash = Ckb::Utils.bin_to_prefix_hex(
        Ckb::Blake2b.digest(Ckb::Utils.hex_to_bin(cell_with_status[:cell][:data])))
      unless returned_cell_hash == configuration[:cell_hash]
        raise "Cell hash doesn't match, something weird is happening!"
      end
      true
    end

    def get_balance
      get_unspent_cells.map { |c| c[:capacity] }.reduce(0, &:+)
    end

    private
    def lock_hash
      @__lock_hash ||= Ckb::Utils.json_script_to_hash(lock_script_json_object)
    end

    def lock_script_json_object
      {
        version: 0,
        binary_hash: api.always_success_cell_hash,
        args: []
      }
    end

    def get_unspent_cells
      to = api.get_tip_number
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_lock_hash(lock_hash, current_from, current_to)
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
        input = {
          previous_output: {
            hash: cell[:out_point][:hash],
            index: cell[:out_point][:index]
          },
          args: []
        }
        inputs << input
        input_capacities += cell[:capacity]
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
