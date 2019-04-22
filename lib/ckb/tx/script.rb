# frozen_string_literal: true

require_relative '../blake2b'

module Ckb
  class Script
    attr_accessor :binary_hash, :args

    def initialize(binary_hash:, args: [])
      @binary_hash = binary_hash
      @args = args
    end

    # @return [Integer]
    def calculate_capacity
      capacity = 1 + (@args || []).map(&:bytesize).reduce(0, &:+)
      capacity += Ckb::Utils.hex_to_bin(@binary_hash).bytesize if @binary_hash
      capacity
    end

    # @return [String] "0x..."
    def to_hash
      s = Ckb::Blake2b.new
      s << Ckb::Utils.hex_to_bin(@binary_hash) if @binary_hash
      (@args || []).each do |arg|
        s << Ckb::Utils.delete_prefix(arg)
      end
      Ckb::Utils.bin_to_hex(s.digest)
    end

    def to_h
      {
        binary_hash: @binary_hash,
        args: @args
      }
    end

    def self.from_h(h)
      return h if h.is_a?(Script)

      new(
        binary_hash: h[:binary_hash],
        args: h[:args]
      )
    end
  end
end
