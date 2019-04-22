# frozen_string_literal: true

require_relative 'script'

module Ckb
  class Output
    attr_accessor :capacity, :data, :lock, :type

    # @param capacity [String]
    # @param data [String]
    # @param lock [Ckb::Script]
    # @param type [Ckb::Script | nil]
    def initialize(capacity:, lock:, data: '0x', type: nil)
      @capacity = capacity.to_s
      @data = data
      @lock = lock
      @type = type
    end

    def calculate_min_capacity
      capacity = 8 + @data.bytesize + @lock.calculate_capacity
      capacity += @type.calculate_capacity if @type
      capacity
    end

    def to_h
      {
        capacity: @capacity,
        data: @data,
        lock: @lock.to_h,
        type: @type && @type.to_h
      }
    end

    def self.from_h(h)
      return h if h.is_a?(Output)

      new(
        capacity: h[:capacity],
        data: h[:data] || '0x',
        lock: Script.from_h(h[:lock]),
        type: h[:type].nil? ? nil : Script.from_h(h[:type])
      )
    end
  end
end
