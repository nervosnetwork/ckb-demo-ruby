# frozen_string_literal: true

require 'secp256k1'

require_relative '../blake2b'
require_relative 'out_point'
require_relative 'input'
require_relative 'script'
require_relative 'output'

module Ckb
  class Transaction
    attr_reader :version, :deps, :inputs, :outputs, :witnesses

    def initialize(version: 0, deps: [], inputs: [], outputs: [], witnesses: [])
      @version = version
      @deps = deps
      @inputs = inputs
      @outputs = outputs
      @witnesses = witnesses
    end

    def self.from_h(h)
      return h if h.is_a?(Transaction)

      new(
        version: h[:version],
        deps: h[:deps],
        inputs: h[:inputs].map { |i| Input.from_h(i) },
        outputs: h[:outputs].map { |o| Output.from_h(o) },
        witnesses: h[:witnesses]
      )
    end

    def sign_sighash_all_inputs(key)
      signed_inputs = self.class.sign_sighash_all_inputs(@inputs, @outputs, key.privkey)
      self.class.new(
        version: version,
        deps: deps,
        inputs: signed_inputs,
        outputs: outputs,
        witnesses: witnesses
      )
    end

    # @return [Ckb::Input[]]
    def self.sign_sighash_multiple_anyonecanpay_inputs(inputs, outputs, privkey)
      sign_sighash_inputs(inputs, outputs, privkey, 0x84)
    end

    # @return [Ckb::Input[]]
    def self.sign_sighash_all_anyonecanpay_inputs(inputs, outputs, privkey)
      sign_sighash_inputs(inputs, outputs, privkey, 0x81)
    end

    # In Ruby, bytes are represented using String, since JSON has no native byte arrays,
    # CKB convention bytes passed with a "0x" prefix hex encoding, hence we
    # have to do type conversions here.
    def normalize_for_json!
      @inputs.each do |input|
        input.args = input.args.map do |arg|
          Ckb::Utils.bin_to_hex(
            Ckb::Utils.delete_prefix(arg)
          )
        end
      end

      @outputs.each do |output|
        output.data = Ckb::Utils.bin_to_hex(
          Ckb::Utils.delete_prefix(output.data)
        )
        output.lock.args = output.lock.args.map do |arg|
          Ckb::Utils.bin_to_hex(
            Ckb::Utils.delete_prefix(arg)
          )
        end

        next unless output.type

        output.type.args = output.type.args.map do |arg|
          Ckb::Utils.bin_to_hex(
            Ckb::Utils.delete_prefix(arg)
          )
        end
      end

      self
    end

    def to_h
      {
        version: @version,
        deps: @deps,
        inputs: @inputs.map(&:to_h),
        outputs: @outputs.map(&:to_h),
        witnesses: @witnesses
      }
    end

    def self.sign_sighash_all_inputs(inputs, outputs, privkey)
      s = Ckb::Blake2b.new
      sighash_type = 0x1.to_s
      s.update(sighash_type)
      inputs.each do |input|
        s.update(Ckb::Utils.hex_to_bin(input.previous_output.hash))
        s.update(input.previous_output.index.to_s)
      end
      outputs.each do |output|
        s.update(output.capacity.to_s)
        s.update(
          Ckb::Utils.hex_to_bin(
            output.lock.to_hash
          )
        )
        next unless output.type

        s.update(
          Ckb::Utils.hex_to_bin(
            output.type.to_hash
          )
        )
      end
      privkey_bin = Ckb::Utils.hex_to_bin(privkey)
      key = Secp256k1::PrivateKey.new(privkey: privkey_bin)
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
      signature_hex = Ckb::Utils.bin_to_hex(signature)

      inputs.map do |input|
        input.args += [signature_hex, sighash_type]
        input
      end
    end

    # @param inputs [[Ckb::Input]]
    # @param outputs [[Ckb::Output]]
    # @param privkey [String] "0x..."
    # @param type [Integer] 0x81
    def self.sign_sighash_inputs(inputs, outputs, privkey, type)
      privkey_bin = Ckb::Utils.hex_to_bin(privkey)
      key = Secp256k1::PrivateKey.new(privkey: privkey_bin)

      inputs.map do |input|
        sighash_type = type.to_s
        s = Ckb::Blake2b.new
        s.update(sighash_type)
        s.update(
          Ckb::Utils.hex_to_bin(
            input.previous_output.hash
          )
        )
        s.update(
          input.previous_output.index.to_s
        )
        outputs.each do |output|
          s.update(output.capacity.to_s)
          s.update(
            Ckb::Utils.hex_to_bin(
              output.lock.to_hash
            )
          )
          next unless output.type

          s.update(
            Ckb::Utils.hex_to_bin(
              output.type.to_hash
            )
          )
        end

        signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
        signature_hex = Ckb::Utils.bin_to_hex(signature)

        # output(s) will be filled when assembling the transaction
        input.args += [signature_hex, sighash_type]
        input
      end
    end
  end
end
