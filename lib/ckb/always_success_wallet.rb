require_relative "api"
require_relative "utils"
require_relative "blake2b"

module Ckb
  class AlwaysSuccessWallet
    attr_reader :api

    def initialize(api)
      @api = api
    end

    def send_capacity(target_address, capacity)
      i = gather_inputs(capacity, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [
        {
          capacity: capacity,
          data: "",
          lock: target_address
        }
      ]
      if input_capacities > capacity
        outputs << {
          capacity: input_capacities - capacity,
          data: "",
          lock: self.address
        }
      end
      tx = {
        version: 0,
        deps: [api.always_success_out_point],
        inputs: i.inputs,
        outputs: outputs
      }
      api.send_transaction(tx)
    end

    # type: :mruby or :c
    def install_cell!(processed_cell_filename, type: :c)
      data = File.read(processed_cell_filename)
      cell_hash = Ckb::Utils.bin_to_prefix_hex(Ckb::Blake2b.digest(data))
      output = {
        capacity: 0,
        data: data,
        lock: address
      }
      output[:capacity] = Ckb::Utils.calculate_cell_min_capacity(output)

      i = gather_inputs(output[:capacity], MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [output]
      if input_capacities > output[:capacity]
        outputs << {
          capacity: input_capacities - output[:capacity],
          data: "",
          lock: address
        }
      end

      tx = {
        version: 0,
        deps: [api.always_success_out_point],
        inputs: i.inputs,
        outputs: outputs
      }
      hash = api.send_transaction(tx)
      {
        out_point: {
          hash: hash,
          index: 0
        },
        cell_hash: cell_hash,
        type: type
      }
    end

    # install mruby-contracts
    def install_mruby_cell!(processed_cell_filename)
      install_cell!(processed_cell_filename, type: :mruby)
    end

    # install ckb-system-scripts
    def install_c_cell!(processed_cell_filename)
      install_cell!(processed_cell_filename, type: :c)
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

    def address
      unlock_type_hash
    end

    private
    def unlock_type_hash
      @__unlock_type_hash ||= Ckb::Utils.json_script_to_type_hash(unlock_script_json_object)
    end

    def unlock_script_json_object
      {
        version: 0,
        reference: api.always_success_cell_hash,
        signed_args: [],
        args: []
      }
    end

    def get_unspent_cells
      to = api.get_tip_number
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_type_hash(unlock_type_hash, current_from, current_to)
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
          unlock: unlock_script_json_object
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
