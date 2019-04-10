require "test_helper"

class Ckb::UtilsTest < Minitest::Test
  def setup
    @hex = "abdc12"
    @bin = [@hex].pack("H*")
  end

  def test_hex_to_bin
    assert Ckb::Utils.hex_to_bin(@hex) == Ckb::Utils.hex_to_bin("0x#{@hex}")
  end

  def test_bin_to_hex
    bin = [@hex].pack("H*")
    assert Ckb::Utils.bin_to_hex(bin) == @hex
  end

  def test_bin_to_prefix_hex
    assert Ckb::Utils.bin_to_prefix_hex(@bin) == "0x#{@hex}"
  end

  def test_calculate_cell_min_capacity
    output = {
      capacity: 5000000,
      data: "",
      lock: {
        args: [],
        binary_hash: "0x0000000000000000000000000000000000000000000000000000000000000000",
        version: 0
      }
    }

    min_capacity = 41

    assert_equal Ckb::Utils.calculate_cell_min_capacity(output), min_capacity
  end

  def test_normalize_tx_for_json
    transaction = {
      deps: [],
      hash: "0x3abd21e6e51674bb961bb4c5f3cee9faa5da30e64be10628dc1cef292cbae324",
      inputs: [
        {
          previous_output: {
              hash: "0x0000000000000000000000000000000000000000000000000000000000000000",
              index: 4294967295
          },
          args: []
        }
      ],
      outputs: [
        {
          capacity: 5000000,
          data: "0x",
          lock: {
            args: ["0x616263"],
            binary_hash: "0x0000000000000000000000000000000000000000000000000000000000000000",
            version: 0
          },
          type: nil
        }
      ],
      witnesses: [
        {
          data: ["0x", "0x616263"]
        }
      ]
    }

    tx = {
      deps: [],
      hash: "0x3abd21e6e51674bb961bb4c5f3cee9faa5da30e64be10628dc1cef292cbae324",
      inputs: [
        {
          previous_output: {
              hash: "0x0000000000000000000000000000000000000000000000000000000000000000",
              index: 4294967295
          },
          args: []
        }
      ],
      outputs: [
        {
          capacity: 5000000,
          data: "",
          lock: {
            args: ["abc"],
            binary_hash: "0x0000000000000000000000000000000000000000000000000000000000000000",
            version: 0
          },
          type: nil
        }
      ],
      witnesses: [
        {
          data: ["", "abc"]
        }
      ]
    }

    assert_equal Ckb::Utils.normalize_tx_for_json!(tx), transaction
  end
end
