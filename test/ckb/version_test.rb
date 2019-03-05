require "test_helper"

class Ckb::VersionTest < Minitest::Test
  def test_version
    refute_nil ::Ckb::VERSION
  end
end
