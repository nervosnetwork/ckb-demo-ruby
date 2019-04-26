require 'test_helper'

class Ckb::OutputTest < Minitest::Test
  def test_calculate_min_capacity
    output = Ckb::Output.from_h(
      capacity: 5_000_000,
      data: '',
      lock: {
        args: [],
        code_hash: '0x0000000000000000000000000000000000000000000000000000000000000000'
      }
    )

    min_capacity = 41

    assert_equal output.calculate_min_capacity, min_capacity
  end
end
