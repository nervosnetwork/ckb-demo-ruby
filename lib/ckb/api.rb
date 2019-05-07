require_relative 'utils'
require_relative 'blake2b'

require 'json'
require 'net/http'
require 'uri'

module Ckb
  URL = 'http://localhost:8114'.freeze
  DEFAULT_CONFIGURATION_FILENAME = File.expand_path('../../conf.json', __dir__)

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
      request.body = { id: 1, jsonrpc: '2.0', method: method.to_s, params: params }.to_json
      request['Content-Type'] = 'application/json'
      response = http.request(request)
      result = JSON.parse(response.body, symbolize_names: true)
      raise "jsonrpc error: #{result[:error]}" if result[:error]

      result
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
      @__genesis_block ||= get_block_by_number("0")
    end

    def get_block_hash(block_number)
      rpc_request('get_block_hash', params: [block_number])[:result]
    end

    def get_block(block_hash_hex)
      rpc_request('get_block', params: [block_hash_hex])[:result]
    end

    def get_block_by_number(block_number)
      rpc_request('get_block_by_number', params: [block_number.to_s])[:result]
    end

    def get_tip_header
      rpc_request('get_tip_header')[:result]
    end

    def get_tip_block_number
      rpc_request('get_tip_block_number')[:result]
    end

    alias get_tip_number get_tip_block_number

    def get_cells_by_lock_hash(hash_hex, from, to)
      params = [hash_hex, from, to]
      rpc_request('get_cells_by_lock_hash', params: params)[:result]
    end

    def get_transaction(tx_hash_hex)
      rpc_request('get_transaction', params: [tx_hash_hex])[:result]
    end

    def get_live_cell(out_point)
      # This way we can detect type errors early instead of weird RPC errors
      normalized_out_point = {
        tx_hash: out_point[:tx_hash],
        index: out_point[:index]
      }
      rpc_request('get_live_cell', params: [normalized_out_point])[:result]
    end

    def send_transaction(transaction)
      tx = transaction.normalize_for_json!.to_h
      rpc_request('send_transaction', params: [tx])[:result]
    end

    def local_node_info
      rpc_request('local_node_info')[:result]
    end

    def trace_transaction(transaction)
      rpc_request('trace_transaction', params: [transaction])[:result]
    end

    def get_transaction_trace(hash)
      rpc_request('get_transaction_trace', params: [hash])[:result]
    end

    def get_current_epoch
      rpc_request('get_current_epoch')
    end
  end
end
