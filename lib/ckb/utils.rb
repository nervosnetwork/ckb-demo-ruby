require "secp256k1"

module Ckb
  MIN_CELL_CAPACITY = 40
  MIN_ERC20_CELL_CAPACITY = 48

  module Utils
    def self.hex_to_bin(s)
      if s.start_with?("0x")
        s = s[2..-1]
      end
      s.each_char.each_slice(2).map(&:join).map(&:hex).map(&:chr).join
    end

    def self.bin_to_hex(s)
      s.bytes.map { |b| b.to_s(16).rjust(2, "0") }.join
    end

    def self.bin_to_prefix_hex(s)
      "0x#{bin_to_hex(s)}"
    end

    def self.extract_pubkey(privkey_bin)
      Secp256k1::PrivateKey.new(privkey: privkey_bin).pubkey.serialize
    end
  end
end
