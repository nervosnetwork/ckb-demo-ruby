require "test_helper"

class Ckb::ApiTest < Minitest::Test
  attr_reader :api, :type_hash

  def setup
    skip("not test rpc") if ENV["SKIP_RPC_TESTS"]
    @api = Ckb::Api.new
    @type_hash = "0x0da2fe99fe549e082d4ed483c2e968a89ea8d11aabf5d79e5cbf06522de6e674"
  end

  def test_genesis_block
    result = api.genesis_block
    refute_nil result
  end

  def test_get_block_hash
    result = api.get_block_hash(1)
    refute_nil result
  end

  def test_get_block
    genesis_block_hash = api.get_block_hash(0)
    result = api.get_block(genesis_block_hash)
    refute_nil result
    assert_equal genesis_block_hash, result[:header][:hash]
  end

  def test_get_tip_header
    result = api.get_tip_header
    refute_nil result
    assert result[:number] > 0
  end

  def test_get_tip_block_number
    result = api.get_tip_block_number
    refute_nil result
    assert result > 0
  end

  def test_get_tip_number
    result = api.get_tip_number
    refute_nil result
    assert result > 0
  end

  def test_get_cells_by_type_hash
    result = api.get_cells_by_type_hash(type_hash, 1, 100)
    refute_nil result
  end

  def test_get_transaction
    genesis_block = api.genesis_block
    tx = genesis_block[:transactions].first
    result = api.get_transaction(tx[:hash])
    refute_nil result
    assert_equal tx[:hash], result[:hash]
  end

  def test_get_live_cell
    cells = api.get_cells_by_type_hash(type_hash, 1, 100)
    result = api.get_live_cell(cells[0][:out_point])
    refute_nil result
  end

  def test_send_transaction
    tx = {
      version: 0,
      deps: [],
      inputs: [],
      outputs: []
    }

    result = api.send_transaction(tx)
    refute_nil result
  end

  def test_local_node_info
    result = api.local_node_info
    refute_nil result
    refute result[:addresses].empty?
    refute result[:node_id].empty?
  end

  def test_trace_transaction
    tx = {
      version: 2,
      deps: [],
      inputs: [],
      outputs: []
    }
    result = api.trace_transaction(tx)
    refute_nil result
  end

  def test_get_transaction_trace
    trace_tx_hash = "0xd91110fe20b7137c884d5c515f591ceda89a177bf06c1a3eb99c8a970dda2cf5"
    result = api.get_transaction_trace(trace_tx_hash)
    refute_nil result
  end
end
