require 'json'
require 'net/http'
require 'uri'
require 'sha3'

module Ckb
  URL = "http://localhost:3030"

  def self.hex_to_bin(s)
    if s.start_with?("0x")
      s = s[2..-1]
    end
    s.each_char.each_slice(2).map(&:join).map(&:hex).map(&:chr).join
  end

  def self.bin_to_hex(s)
    s.bytes.map { |b| b.to_s(16).rjust(2, "0") }.join
  end

  class Api
    attr_reader :uri

    def initialize(host: URL)
      @uri = URI(host)
    end

    def rpc_request(method, params: nil)
      response = Net::HTTP.post(
        uri,
        "{\"id\": 1, \"jsonrpc\": \"2.0\", \"method\": \"#{method}\", \"params\": #{params.to_json}}",
        "Content-Type" => "application/json")
      JSON.parse(response.body, symbolize_names: true)
    end

    def calculate_redeem_script_hash(pubkey_bin)
      outpoint = get_system_redeem_script_outpoint
      s = SHA3::Digest::SHA256.new
      s << outpoint.hash
      s << [outpoint.index].pack("V")
      s << "|"
      s << Ckb.bin_to_hex(pubkey_bin)
      s.digest
    end

    # Returns a default secp256k1-sha3 input unlock contract included in CKB
    def get_system_redeem_script_outpoint
      OpenStruct.new(hash: Ckb.hex_to_bin(genesis_block[:transactions][0][:hash]),
                     index: 0)
    end

    def genesis_block
      @__genesis_block ||= get_block(get_block_hash(0))
    end

    def get_block_hash(block_number)
      rpc_request("get_block_hash", params: [block_number])[:result]
    end

    def get_block(block_hash)
      rpc_request("get_block", params: [block_hash])[:result]
    end
  end
end
