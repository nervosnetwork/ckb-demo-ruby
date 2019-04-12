# coding: utf-8
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

    def self.json_script_to_hash(script)
      s = Ckb::Blake2b.new
      if script[:binary_hash]
        s << hex_to_bin(script[:binary_hash])
      end
      (script[:args] || []).each do |arg|
        s << arg
      end
      bin_to_prefix_hex(s.digest)
    end

    def self.sign_sighash_multiple_anyonecanpay_inputs(inputs, outputs, privkey)
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      inputs.map do |input|
        sighash_type = 0x84.to_s
        s = Ckb::Blake2b.new
        s.update(sighash_type)
        s.update(Ckb::Utils.hex_to_bin(input[:previous_output][:hash]))
        s.update(input[:previous_output][:index].to_s)
        outputs.each do |output|
          s.update(output[:capacity].to_s)
          s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_hash(output[:lock])))
          if output[:type]
            s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_hash(output[:type])))
          end
        end

        signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
        signature_hex = Ckb::Utils.bin_to_hex(signature)

        # output(s) will be filled when assembling the transaction
        args = input[:args] + [signature_hex, sighash_type]
        input.merge(args: args)
      end
    end

    def self.sign_sighash_all_anyonecanpay_inputs(inputs, outputs, privkey)
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      inputs.map do |input|
        sighash_type = 0x81.to_s
        s = Ckb::Blake2b.new
        s.update(sighash_type)
        s.update(Ckb::Utils.hex_to_bin(input[:previous_output][:hash]))
        s.update(input[:previous_output][:index].to_s)
        outputs.each do |output|
          s.update(output[:capacity].to_s)
          s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_hash(output[:lock])))
          if output[:type]
            s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_hash(output[:type])))
          end
        end

        signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
        signature_hex = Ckb::Utils.bin_to_hex(signature)

        args = input[:args] + [signature_hex, sighash_type]
        input.merge(args: args)
      end
    end

    def self.sign_sighash_all_inputs(inputs, outputs, privkey)
      s = Ckb::Blake2b.new
      sighash_type = 0x1.to_s
      s.update(sighash_type)
      inputs.each do |input|
        s.update(Ckb::Utils.hex_to_bin(input[:previous_output][:hash]))
        s.update(input[:previous_output][:index].to_s)
      end
      outputs.each do |output|
        s.update(output[:capacity].to_s)
        s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_hash(output[:lock])))
        if output[:type]
          s.update(Ckb::Utils.hex_to_bin(Ckb::Utils.json_script_to_hash(output[:type])))
        end
      end
      key = Secp256k1::PrivateKey.new(privkey: privkey)
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
      signature_hex = Ckb::Utils.bin_to_hex(signature)

      inputs.map do |input|
        args = input[:args] + [signature_hex, sighash_type]
        input.merge(args: args)
      end
    end

    def self.calculate_script_capacity(script)
      capacity = 1 + (script[:args] || []).map { |arg| arg.bytesize }.reduce(0, &:+)
      if script[:binary_hash]
        capacity += Ckb::Utils.hex_to_bin(script[:binary_hash]).bytesize
      end
      capacity
    end

    def self.calculate_cell_min_capacity(output)
      capacity = 8 + output[:data].bytesize + calculate_script_capacity(output[:lock])
      if type = output[:type]
        capacity += calculate_script_capacity(type)
      end
      capacity
    end

    # In Ruby, bytes are represented using String, since JSON has no native byte arrays,
    # CKB convention bytes passed with a “0x” prefix hex encoding, hence we
    # have to do type conversions here.
    def self.normalize_tx_for_json!(transaction)
      transaction[:inputs].each do |input|
        input[:args] = input[:args].map do |arg|
          Ckb::Utils.bin_to_prefix_hex(arg)
        end
      end
      transaction[:outputs].each do |output|
        output[:data] = Ckb::Utils.bin_to_prefix_hex(output[:data])
        output[:lock][:args] = output[:lock][:args].map do |arg|
          Ckb::Utils.bin_to_prefix_hex(arg)
        end

        if output[:type]
          output[:type][:args] = output[:type][:args].map do |arg|
            Ckb::Utils.bin_to_prefix_hex(arg)
          end
        end
      end
      transaction
    end
  end
end
