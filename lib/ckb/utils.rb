require "secp256k1"

module Ckb
  MIN_CELL_CAPACITY = 40
  MIN_UDT_CELL_CAPACITY = 48

  module Utils
    def self.hex_to_bin(s)
      if s.start_with?("0x")
        s = s[2..-1]
      end
      [s].pack("H*")
    end

    def self.bin_to_hex(s)
      s.unpack("H*")[0]
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
          if output[:type]
            s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(output[:type])))
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
          if output[:type]
            s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(output[:type])))
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
        if output[:type]
          s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_type_hash(output[:type])))
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
      if type = output[:type]
        capacity += 1
        capacity += (type[:args] || []).map { |arg| arg.bytesize }.reduce(0, &:+)
        if type[:reference]
          capacity += Ckb::Utils.hex_to_bin(type[:reference]).bytesize
        end
        if type[:binary]
          capacity += type[:binary].bytesize
        end
        capacity += (type[:signed_args] || []).map { |arg| arg.bytesize }.reduce(&:+)
      end
      capacity
    end

    # In Ruby, bytes are represented using String, since JSON has no native byte arrays,
    # CKB convention bytes passed with a “0x” prefix hex encoding, hence we
    # have to do type conversions here.
    def self.normalize_tx_for_json!(transaction)
      transaction[:inputs].each do |input|
        input[:unlock][:args] = input[:unlock][:args].map do |arg|
          Ckb::Utils.bin_to_prefix_hex(arg)
        end
        input[:unlock][:signed_args] = input[:unlock][:signed_args].map do |arg|
          Ckb::Utils.bin_to_prefix_hex(arg)
        end
        if input[:binary]
          input[:binary] = Ckb::Utils.bin_to_prefix_hex(input[:binary])
        end
      end
      transaction[:outputs].each do |output|
        output[:data] = Ckb::Utils.bin_to_prefix_hex(output[:data])

        if output[:type]
          output[:type][:args] = output[:type][:args].map do |arg|
            Ckb::Utils.bin_to_prefix_hex(arg)
          end
          output[:type][:signed_args] = output[:type][:signed_args].map do |arg|
            Ckb::Utils.bin_to_prefix_hex(arg)
          end
          if output[:type][:binary]
            output[:type][:binary] = Ckb::Utils.bin_to_prefix_hex(output[:type][:binary])
          end
        end
      end
      transaction
    end
  end
end
