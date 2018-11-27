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
      response = Net::HTTP.post(
        uri,
        "{\"id\": 1, \"jsonrpc\": \"2.0\", \"method\": \"#{method}\", \"params\": #{params.to_json}}",
        "Content-Type" => "application/json")
      result = JSON.parse(response.body, symbolize_names: true)
      if result[:error]
        raise "jsonrpc error: #{result[:error]}"
      end
      result
    end

    # Returns a default secp256k1-sha3 input unlock contract included in CKB
    def basic_verify_script_outpoint
      OpenStruct.new(hash_value: Ckb::Utils.hex_to_bin(genesis_block[:transactions][0][:hash]),
                     index: 0)
    end

    def verify_cell_hash_bin
      SHA3::Digest::SHA256.digest(genesis_block[:transactions][0][:transaction][:outputs][0][:data].pack("c*"))
    end

    # Returns a contract that could load Ruby source code in CKB
    def mruby_script_outpoint
      {
        hash: genesis_block[:transactions][0][:hash],
        index: 2
      }
    end

    def mruby_cell_hash
      hash_bin = SHA3::Digest::SHA256.digest(genesis_block[:transactions][0][:transaction][:outputs][2][:data].pack("c*"))
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

    def send_transaction(transaction)
      # In Ruby, bytes are represented using String, but Rust uses Vec<u8>
      # to represent bytes, which needs raw array in JSON part, hence we
      # have to do type conversions here.
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
      rpc_request("send_transaction", params: [transaction])[:result]
    end
  end
end
