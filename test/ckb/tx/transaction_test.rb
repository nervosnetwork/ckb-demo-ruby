require 'test_helper'

class Ckb::TransactionTest < Minitest::Test
  def test_normalize_tx_for_json
    transaction = Ckb::Transaction.from_h(
      deps: [],
      hash: '0x3abd21e6e51674bb961bb4c5f3cee9faa5da30e64be10628dc1cef292cbae324',
      inputs: [
        {
          previous_output: {
            hash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            index: 4_294_967_295
          },
          args: []
        }
      ],
      outputs: [
        {
          capacity: 5_000_000,
          data: '0x',
          lock: {
            args: ['0x616263'],
            binary_hash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            version: 0
          },
          type: nil
        }
      ]
    )

    tx = Ckb::Transaction.from_h(
      deps: [],
      hash: '0x3abd21e6e51674bb961bb4c5f3cee9faa5da30e64be10628dc1cef292cbae324',
      inputs: [
        {
          previous_output: {
            hash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            index: 4_294_967_295
          },
          args: []
        }
      ],
      outputs: [
        {
          capacity: 5_000_000,
          data: '',
          lock: {
            args: ['abc'],
            binary_hash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            version: 0
          },
          type: nil
        }
      ]
    )

    assert_equal tx.normalize_for_json!.to_h, transaction.to_h
  end
end
