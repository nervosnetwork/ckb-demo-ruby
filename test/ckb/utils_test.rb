require 'test_helper'

class Ckb::UtilsTest < Minitest::Test
  def setup
    @hex = 'abdc12'
    @bin = [@hex].pack('H*')
  end

  def test_hex_to_bin
    assert Ckb::Utils.hex_to_bin(@hex) == Ckb::Utils.hex_to_bin("0x#{@hex}")
  end

  def test_bin_to_hex
    assert Ckb::Utils.bin_to_hex(@bin) == "0x#{@hex}"
  end
end
