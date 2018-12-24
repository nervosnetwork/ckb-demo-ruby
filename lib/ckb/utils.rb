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

    def self.sign_sighash_multiple_anyonecanpay_inputs(inputs, outputs, privkey)
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      inputs.map do |input|
        sighash_type = 0x84.to_s
        s = SHA3::Digest::SHA256.new
        s.update(sighash_type)
        s.update(Ckb::Utils.hex_to_bin(input[:previous_output][:hash]))
        s.update(input[:previous_output][:index].to_s)
        s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(input[:unlock])))
        outputs.each do |output|
          s.update(output[:capacity].to_s)
          s.update(Ckb::Utils.hex_to_bin(output[:lock]))
          if output[:contract]
            s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(output[:contract])))
          end
        end

        signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
        signature_hex = Ckb::Utils.bin_to_hex(signature)

        # output(s) will be filled when assembling the transaction
        unlock = input[:unlock].merge(args: [signature_hex, sighash_type])
        input.merge(unlock: unlock)
      end
    end

    def self.sign_sighash_all_anyonecanpay_inputs(inputs, outputs, privkey)
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      inputs.map do |input|
        sighash_type = 0x81.to_s
        s = SHA3::Digest::SHA256.new
        s.update(sighash_type)
        s.update(Ckb::Utils.hex_to_bin(input[:previous_output][:hash]))
        s.update(input[:previous_output][:index].to_s)
        s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(input[:unlock])))
        outputs.each do |output|
          s.update(output[:capacity].to_s)
          s.update(Ckb::Utils.hex_to_bin(output[:lock]))
          if output[:contract]
            s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(output[:contract])))
          end
        end

        signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
        signature_hex = Ckb::Utils.bin_to_hex(signature)

        unlock = input[:unlock].merge(args: [signature_hex, sighash_type])
        input.merge(unlock: unlock)
      end
    end

    def self.sign_sighash_all_inputs(inputs, outputs, privkey)
      s = SHA3::Digest::SHA256.new
      sighash_type = 0x1.to_s
      s.update(sighash_type)
      inputs.each do |input|
        s.update(Ckb::Utils.hex_to_bin(input[:previous_output][:hash]))
        s.update(input[:previous_output][:index].to_s)
        s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(input[:unlock])))
      end
      outputs.each do |output|
        s.update(output[:capacity].to_s)
        s.update(Ckb::Utils.hex_to_bin(output[:lock]))
        if output[:contract]
          s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(output[:contract])))
        end
      end
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
      signature_hex = Ckb::Utils.bin_to_hex(signature)

      inputs.map do |input|
        unlock = input[:unlock].merge(args: [signature_hex, sighash_type])
        input.merge(unlock: unlock)
      end
    end

    def self.calculate_cell_min_capacity(output)
      capacity = 8 + output[:data].bytesize + Ckb::Utils.hex_to_bin(output[:lock]).bytesize
      if contract = output[:contract]
        capacity += 1
        capacity += (contract[:args] || []).map { |arg| arg.bytesize }.reduce(0, &:+)
        if contract[:reference]
          capacity += Ckb::Utils.hex_to_bin(contract[:reference]).bytesize
        end
        if contract[:binary]
          capacity += contract[:binary].bytesize
        end
        capacity += (contract[:signed_args] || []).map { |arg| arg.bytesize }.reduce(&:+)
      end
      capacity
    end

    # In Ruby, bytes are represented using String, but Rust uses Vec<u8>
    # to represent bytes, which needs raw array in JSON part, hence we
    # have to do type conversions here.
    def self.normalize_tx_for_json!(transaction)
      transaction[:inputs].each do |input|
        input[:unlock][:args] = input[:unlock][:args].map do |arg|
          if arg.is_a? String
            arg.bytes.to_a
          else
            arg
          end
        end
        input[:unlock][:signed_args] = input[:unlock][:signed_args].map do |arg|
          if arg.is_a? String
            arg.bytes.to_a
          else
            arg
          end
        end
        if input[:binary] && input[:binary].is_a?(String)
          input[:binary] = input[:binary].bytes.to_a
        end
      end
      transaction[:outputs].each do |output|
        if output[:data].is_a? String
          output[:data] = output[:data].bytes.to_a
        end
        if output[:contract]
          output[:contract][:args] = output[:contract][:args].map do |arg|
            if arg.is_a? String
              arg.bytes.to_a
            else
              arg
            end
          end
          output[:contract][:signed_args] = output[:contract][:signed_args].map do |arg|
            if arg.is_a? String
              arg.bytes.to_a
            else
              arg
            end
          end
          if output[:contract][:binary] && output[:contract][:binary].is_a?(String)
            output[:contract][:binary] = output[:contract][:binary].bytes.to_a
          end
        end
      end
      transaction
    end
  end
end
