# frozen_string_literal: true

require_relative "out_point"

module Ckb
  class Input
    attr_accessor :previous_output, :args

    # @param previous_output [Ckb::OutPoint]
    # @param args [String[]]
    # @param valid_since [String]
    def initialize(previous_output:, args: [], valid_since: '0')
      @previous_output = previous_output
      @args = args
      @valid_since = valid_since
    end

    def to_h
      {
        previous_output: @previous_output.to_h,
        args: @args,
        valid_since: @valid_since
      }
    end

    def self.from_h(h)
      return h if h.is_a?(Input)
      
      new(
        previous_output: OutPoint.from_h(h[:previous_output]),
        args: h[:args],
        valid_since: h[:valid_since]
      )
    end
  end
end
