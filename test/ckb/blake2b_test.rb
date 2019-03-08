require "test_helper"

class Ckb::Blake2bTest < Minitest::Test
  def setup
    @fixture = [
      {
        str: "",
        digest: "44f4c69744d5f8c55d642062949dcae49bc4e7ef43d388c5a12f42b5633d163e"
      },
      {
        str: "The quick brown fox jumps over the lazy dog",
        digest: "abfa2c08d62f6f567d088d6ba41d3bbbb9a45c241a8e3789ef39700060b5cee2"
      }
  ]
  end

  def test_hash_data
    @fixture.each do |obj|
      blake2b = Ckb::Blake2b.new
      blake2b.update(obj[:str])
      assert Ckb::Utils.bin_to_hex(blake2b.digest) == obj[:digest]
    end
  end

end
