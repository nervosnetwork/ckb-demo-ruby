# frozen_string_literal: true

module Ckb
  class OutPoint
    attr_accessor :tx_hash, :index

    def initialize(tx_hash:, index:)
      @tx_hash = tx_hash
      @index = index
    end

    def to_h
      {
        tx_hash: @tx_hash,
        index: @index
      }
    end

    # @param h [Hash]
    def self.from_h(h)
      return h if h.is_a?(OutPoint)

      new(
        tx_hash: h[:hash],
        index: h[:index]
      )
    end
  end
end
