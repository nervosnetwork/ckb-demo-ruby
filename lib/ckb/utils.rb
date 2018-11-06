module Ckb
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
  end
end
