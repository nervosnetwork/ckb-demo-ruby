# frozen_string_literal: true

require "rbnacl"

module Ckb
  class Blake2b
    PERSONALIZATION = "ckb-default-hash"
    DIGEST_SIZE = 32

    def initialize(_opts = {})
      @blake2b = self.class.generate
    end

    # @param [String] string, not bin
    def update(message)
      @blake2b.update(message)
      @blake2b
    end

    def digest
      @blake2b.digest
    end

    def self.generate(_opts = {})
      ::RbNaCl::Hash::Blake2b.new(
        personal: PERSONALIZATION,
        digest_size: DIGEST_SIZE
      )
    end
  end
end
