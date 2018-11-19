require "secp256k1"

module Ckb
  MIN_CELL_CAPACITY = 40
  MIN_UDT_CELL_CAPACITY = 48

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

    def self.extract_pubkey_bin(privkey_bin)
      Secp256k1::PrivateKey.new(privkey: privkey_bin).pubkey.serialize
    end

    def self.json_script_to_type_hash(script)
      s = SHA3::Digest::SHA256.new
      if script[:reference]
        s << hex_to_bin(script[:reference])
      end
      s << "|"
      if script[:binary]
        s << script[:binary]
      end
      (script[:signed_args] || []).each do |arg|
        s << arg
      end
      bin_to_prefix_hex(s.digest)
    end
  end
end
