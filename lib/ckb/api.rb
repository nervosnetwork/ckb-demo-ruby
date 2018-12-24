require_relative 'utils'

require 'json'
require 'net/http'
require 'uri'
require 'sha3'

module Ckb
  URL = "http://localhost:8114"
  DEFAULT_CONFIGURATION_FILENAME = File.expand_path("../../../conf.json", __FILE__)

  class Api
    attr_reader :uri
    attr_reader :mruby_out_point
    attr_reader :mruby_cell_hash

    def initialize(host: URL)
      @uri = URI(host)
    end

    def inspect
      "\#<API@#{uri}>"
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
    def always_success_script_out_point
      {
        hash: genesis_block[:transactions][0][:hash],
        index: 0
      }
    end

    def always_success_cell_hash
      hash_bin = SHA3::Digest::SHA256.digest(
        genesis_block[:transactions][0][:transaction][:outputs][0][:data].pack("c*"))
      Ckb::Utils.bin_to_prefix_hex(hash_bin)
    end

    def set_configuration!(configuration)
      @mruby_out_point = configuration[:out_point]
      @mruby_cell_hash = configuration[:cell_hash]
    end

    def set_and_save_default_configuration!(configuration)
      set_configuration!(configuration)
      save_mruby_configuration!(DEFAULT_CONFIGURATION_FILENAME)
    end

    def load_default_configuration!
      load_mruby_configuration!(DEFAULT_CONFIGURATION_FILENAME)
    end

    def load_mruby_configuration!(configuration_filename)
      set_configuration!(JSON.parse(File.read(configuration_filename), symbolize_names: true))
    end

    def save_mruby_configuration!(configuration_filename)
      conf = {
        out_point: mruby_out_point,
        cell_hash: mruby_cell_hash
      }
      File.write(configuration_filename, conf.to_json)
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
