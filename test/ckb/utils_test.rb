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
      lock: "0da2fe99fe549e082d4ed483c2e968a89ea8d11aabf5d79e5cbf06522de6e674",
      type: {
        args: [],
        binary: "0100000000000000",
        reference: nil,
        signed_args: [],
        version: 0
      }
    }

    min_capacity = 57

    assert Ckb::Utils.calculate_cell_min_capacity(output), min_capacity
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
          unlock: {
              args: [],
              binary: "0x0100000000000000",
              reference: nil,
              signed_args: [],
              version: 0
          }
        }
      ],
      outputs: [
        {
          capacity: 5000000,
          data: "0x",
          lock: "0x0da2fe99fe549e082d4ed483c2e968a89ea8d11aabf5d79e5cbf06522de6e674",
          type: nil
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
          unlock: {
              args: [],
              binary: ["0100000000000000"].pack("H*"),
              reference: nil,
              signed_args: [],
              version: 0
          }
        }
      ],
      outputs: [
        {
          capacity: 5000000,
          data: "",
          lock: "0x0da2fe99fe549e082d4ed483c2e968a89ea8d11aabf5d79e5cbf06522de6e674",
          type: nil
        }
      ]
    }

    assert_equal Ckb::Utils.normalize_tx_for_json!(tx), transaction
  end
end
