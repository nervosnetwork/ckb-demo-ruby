require 'secp256k1'

module Ckb
  module Utils
    def self.hex_to_bin(str)
      str = str[2..-1] if str.start_with?('0x')
      [str].pack('H*')
    end

    def self.valid_hex_string?(hex)
      hex.start_with?('0x') && hex.length.even?
    end

    def self.bin_to_hex(bin_str)
      "0x#{bin_str.unpack('H*')[0]}"
    end

    def self.delete_prefix(str)
      return str[2..-1] if str.start_with?('0x')

      str
    end

    # @param capacity [Integer] Byte
    #
    # @return [Integer] shannon
    def self.byte_to_shannon(capacity)
      capacity * (10**8)
    end
  end

  MIN_CELL_CAPACITY = Utils.byte_to_shannon(40)
  MIN_UDT_CELL_CAPACITY = Utils.byte_to_shannon(48)
end
