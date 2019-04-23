# frozen_string_literal: true

module Ckb
  class OutPoint
    attr_accessor :hash, :index

    def initialize(hash:, index:)
      @hash = hash
      @index = index
    end

    def to_h
      {
        hash: @hash,
        index: @index
      }
    end

    # @param h [Hash]
    def self.from_h(h)
      return h if h.is_a?(OutPoint)

      new(
        hash: h[:hash],
        index: h[:index]
      )
    end
  end
end
