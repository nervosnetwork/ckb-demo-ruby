require_relative 'utils'

require 'json'
require 'net/http'
require 'uri'
require 'sha3'

module Ckb
  URL = "http://localhost:8114"

  class Api
    attr_reader :uri

    def initialize(host: URL)
      @uri = URI(host)
    end

    def rpc_request(method, params: nil)
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = { id: 1, jsonrpc: "2.0", method: "#{method}", params: params }.to_json
      request["Content-Type"] = "application/json"
      response = http.request(request)
      result = JSON.parse(response.body, symbolize_names: true)
      if result[:error]
        raise "jsonrpc error: #{result[:error]}"
      end
      result
    end

    # Returns a default secp256k1-sha3 input unlock contract included in CKB
    def basic_verify_script_out_point
      OpenStruct.new(hash_value: Ckb::Utils.hex_to_bin(genesis_block[:transactions][0][:hash]),
                     index: 0)
    end

    def verify_cell_hash_bin
      SHA3::Digest::SHA256.digest(genesis_block[:transactions][0][:transaction][:outputs][0][:data].pack("c*"))
    end

    # Returns a contract that could load Ruby source code in CKB
    def mruby_script_out_point
      {
        hash: genesis_block[:transactions][0][:hash],
        index: 2
      }
    end

    def mruby_cell_hash
      system_cells = genesis_block[:transactions][0][:transaction][:outputs]
      if system_cells.length < 3
        raise "Cannot find mruby contract cell, please check your configuration"
      end
      hash_bin = SHA3::Digest::SHA256.digest(system_cells[2][:data].pack("c*"))
      Ckb::Utils.bin_to_prefix_hex(hash_bin)
    end

    def genesis_block
      @__genesis_block ||= get_block(get_block_hash(0))
    end

    def get_block_hash(block_number)
      rpc_request("get_block_hash", params: [block_number])[:result]
    end

    def get_block(block_hash_hex)
      rpc_request("get_block", params: [block_hash_hex])[:result]
    end

    def get_tip_number
      rpc_request("get_tip_header")[:result][:raw][:number]
    end

    def get_cells_by_type_hash(hash_hex, from, to)
      params = [hash_hex, from, to]
      rpc_request("get_cells_by_type_hash", params: params)[:result]
    end

    def get_transaction(tx_hash_hex)
      rpc_request("get_transaction", params: [tx_hash_hex])[:result]
    end

    def get_current_cell(out_point)
      # This way we can detect type errors early instead of weird RPC errors
      normalized_out_point = {
        hash: out_point[:hash],
        index: out_point[:index]
      }
      rpc_request("get_current_cell", params: [normalized_out_point])[:result]
    end

    def send_transaction(transaction)
      transaction = Ckb::Utils.normalize_tx_for_json!(transaction)
      rpc_request("send_transaction", params: [transaction])[:result]
    end
  end
end
