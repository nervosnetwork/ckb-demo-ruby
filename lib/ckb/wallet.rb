require 'awesome_print'

require_relative 'api'
require_relative 'tx/transaction'
require_relative 'always_success_wallet'
require_relative 'udt/udt'
require_relative 'utils'
require_relative 'version'
require_relative 'blake2b'
require_relative 'key'

require 'secp256k1'

module Ckb
  VERIFY_SCRIPT = File.read(File.expand_path('../../scripts/secp256k1_blake2b_lock.rb', __dir__))

  class Wallet
    attr_reader :api
    attr_reader :key

    # @param api [Ckb::Api]
    # @param privkey [Ckb::Key]
    def initialize(api, key)
      @api = api
      @key = key
    end

    # @param api [Ckb::Api]
    # @param privkey_hex [String] "0x...."
    def self.from_hex(api, privkey_hex)
      new(api, Ckb::Key.new(privkey_hex))
    end

    def lock
      verify_script
    end

    def get_unspent_cells
      to = api.get_tip_number.to_i
      results = []
      current_from = 1
      while current_from <= to
        current_to = [current_from + 100, to].min
        cells = api.get_cells_by_lock_hash(
          verify_script_hash,
          current_from.to_s,
          current_to.to_s
        )
        results.concat(cells)
        current_from = current_to + 1
      end
      results
    end

    def get_balance
      get_unspent_cells.map { |c| c[:capacity].to_i }.reduce(0, &:+)
    end

    def generate_tx(target_lock, capacity)
      i = gather_inputs(capacity, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [
        Output.new(
          capacity: capacity.to_s,
          data: '0x',
          lock: target_lock
        )
      ]
      if input_capacities > capacity
        outputs << Output.new(
          capacity: (input_capacities - capacity).to_s,
          data: '0x',
          lock: lock
        )
      end

      tx = Transaction.new(
        version: 0,
        deps: [api.mruby_out_point],
        inputs: i.inputs,
        outputs: outputs
      ).sign_sighash_all_inputs(@key)
    end

    def send_capacity(target_lock, capacity)
      tx = generate_tx(target_lock, capacity)
      api.send_transaction(tx)
    end

    def get_transaction(hash)
      api.get_transaction(hash)
    end

    def sign_capacity_for_udt_cell(capacity_to_pay, token_output)
      if capacity_to_pay < token_output.capacity.to_i
        raise 'Not enough capacity paid!'
      end

      i = gather_inputs(capacity_to_pay, MIN_UDT_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [token_output]
      if input_capacities > capacity_to_pay
        outputs << Output.new(
          capacity: (input_capacities - capacity_to_pay).to_s,
          data: '0x',
          lock: lock
        )
      end

      signed_inputs = Ckb::Transaction.sign_sighash_multiple_anyonecanpay_inputs(i.inputs, outputs, @key.privkey)

      Transaction.new(
        version: 0,
        deps: [api.mruby_out_point],
        inputs: signed_inputs,
        outputs: outputs
      )
    end

    # Create a new cell for storing an existing user defined token, you can
    # think this as an ethereum account for a user defined token
    #
    # @param capacity [Integer]
    # @param token_info [Udt::TokenInfo | Udt::FixedAmountTokenInfo]
    #
    # @return [Ckb::OutPoint]
    def create_udt_account_wallet_cell(capacity, token_info)
      if udt_account_wallet(token_info).created?
        raise 'Cell is already created!'
      end

      cell = Output.new(
        capacity: capacity.to_s,
        data: [0].pack('Q<'),
        lock: udt_account_wallet(token_info).lock,
        type: token_info.type
      )
      needed_capacity = cell.calculate_min_capacity
      if capacity < needed_capacity
        raise "Not enough capacity for account cell, needed: #{needed_capacity}"
      end

      i = gather_inputs(capacity, MIN_UDT_CELL_CAPACITY)
      input_capacities = i.capacities

      outputs = [cell]
      if input_capacities > capacity
        outputs << Output.new(
          capacity: (input_capacities - capacity).to_s,
          data: '0x',
          lock: lock
        )
      end
      tx = Transaction.new(
        version: 0,
        deps: [api.mruby_out_point],
        inputs: i.inputs,
        outputs: outputs
      ).sign_sighash_all_inputs(@key)

      tx_hash = api.send_transaction(tx)

      # This is in fact an OutPoint here
      OutPoint.new(
        tx_hash: tx_hash,
        index: 0
      )
    end

    # Create a user defined token with fixed upper amount, subsequent invocations
    # on this method will create different tokens.
    #
    # @param capacity [Integer]
    # @param tokens [Integer]
    # @param rate [Integer] exchange rate, N tokens per capacity
    # @param lock [Ckb::Script]
    def create_fixed_amount_token(capacity, tokens, rate, lock: nil)
      lock ||= verify_script

      i = gather_inputs(capacity, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      ms = Ckb::Blake2b.new
      i.inputs.each do |input|
        ms.update(Ckb::Utils.hex_to_bin(input.previous_output.tx_hash))
        ms.update(input.previous_output.index.to_s)
      end

      info = Udt::FixedAmountTokenInfo.new(
        api,
        Ckb::Utils.bin_to_hex(ms.digest),
        lock,
        @key.pubkey,
        rate
      )

      data = [tokens].pack('Q<')
      outputs = [
        Output.new(
          capacity: capacity.to_s,
          data: data,
          lock: info.genesis_lock,
          type: info.genesis_type
        )
      ]
      if input_capacities > capacity
        outputs << Output.new(
          capacity: (input_capacities - capacity).to_s,
          data: '0x',
          lock: self.lock
        )
      end

      s = Ckb::Blake2b.new
      contract_hash_bin = Ckb::Utils.hex_to_bin(
        outputs[0].type.to_hash
      )
      s.update(contract_hash_bin)
      i.inputs.each do |input|
        s.update(
          Ckb::Utils.hex_to_bin(
            input.previous_output.tx_hash
          )
        )
        s.update(input.previous_output.index.to_s)
      end
      s.update(outputs[0].capacity.to_s)
      s.update(
        Ckb::Utils.hex_to_bin(
          outputs[0].lock.to_hash
        )
      )
      s.update(contract_hash_bin)
      s.update(data)
      if outputs[1]
        s.update(outputs[1].capacity.to_s)
        s.update(
          Ckb::Utils.hex_to_bin(
            outputs[1].lock.to_hash
          )
        )
      end

      privkey_bin = Ckb::Utils.hex_to_bin(@key.privkey)
      key = Secp256k1::PrivateKey.new(privkey: privkey_bin)
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))

      outputs[0].data += signature

      tx = Transaction.new(
        version: 0,
        deps: [api.mruby_out_point],
        inputs: i.inputs,
        outputs: outputs
      ).sign_sighash_all_inputs(@key)
      hash = api.send_transaction(tx)
      OpenStruct.new(tx_hash: hash, token_info: info)
    end

    # @param tokens [Integer]
    # @param token_info [Udt::TokenInfo | Udt::FixedAmountTokenInfo]
    def purchase_fixed_amount_token(tokens, token_info)
      paid_capacity = (tokens + token_info.rate - 1) / token_info.rate
      paid_cell = Output.new(
        capacity: paid_capacity,
        data: '0x',
        lock: token_info.issuer_lock
      )
      needed_capacity = paid_cell.calculate_min_capacity
      if paid_capacity < needed_capacity
        raise "Not enough capacity for account cell, needed: #{needed_capacity}"
      end

      i = gather_inputs(paid_capacity, MIN_CELL_CAPACITY)
      input_capacities = i.capacities

      wallet_cell = udt_account_wallet(token_info).fetch_cell
      udt_genesis_cell = token_info.fetch_cell

      # Those won't require signing
      additional_inputs = [
        Input.new(
          previous_output: OutPoint.new(
            tx_hash: wallet_cell[:out_point][:tx_hash],
            index: wallet_cell[:out_point][:index]
          ),
          args: [],
          since: '0'
        ),
        Input.new(
          previous_output: OutPoint.new(
            tx_hash: udt_genesis_cell[:out_point][:tx_hash],
            index: udt_genesis_cell[:out_point][:index]
          ),
          args: [],
          since: '0'
        )
      ]

      outputs = [
        Output.new(
          capacity: wallet_cell[:capacity].to_s,
          data: [wallet_cell[:amount] + tokens].pack('Q<'),
          lock: Script.from_h(wallet_cell[:lock]),
          type: token_info.type
        ),
        Output.new(
          capacity: udt_genesis_cell[:capacity].to_s,
          data: [udt_genesis_cell[:amount] - tokens].pack('Q<'),
          lock: Script.from_h(udt_genesis_cell[:lock]),
          type: token_info.genesis_type
        ),
        paid_cell
      ]
      if input_capacities > paid_capacity
        outputs << Output.new(
          capacity: (input_capacities - paid_capacity).to_s,
          data: '0x',
          lock: lock
        )
      end

      signed_inputs = Ckb::Transaction.sign_sighash_all_anyonecanpay_inputs(i.inputs, outputs, @key.privkey)
      tx = Transaction.new(
        version: 0,
        deps: [api.mruby_out_point],
        inputs: signed_inputs + additional_inputs,
        outputs: outputs
      )
      api.send_transaction(tx)
    end

    # Issue a new user defined token using current wallet as token superuser
    #
    # @param capacity [Integer]
    # @param token_name [String]
    # @param token [Integer]
    # @param account_wallet [Boolean]
    def create_udt_token(capacity, token_name, tokens, account_wallet: false)
      token_info = created_token_info(token_name, account_wallet: account_wallet)
      wallet = account_wallet ? udt_account_wallet(token_info) : udt_wallet(token_info)

      data = [tokens].pack('Q<')
      s = Ckb::Blake2b.new
      s.update(data)
      puts "Hashing: #{data.unpack('H*')[0]}"
      privkey_bin = Ckb::Utils.hex_to_bin(@key.privkey)
      key = Secp256k1::PrivateKey.new(privkey: privkey_bin)
      puts "Message: #{s.digest.unpack('H*')[0]}"
      signature = key.ecdsa_serialize(key.ecdsa_sign(s.digest, raw: true))
      puts "Signature: #{signature.unpack('H*')[0]}"

      i = gather_inputs(capacity, MIN_UDT_CELL_CAPACITY)
      input_capacities = i.capacities

      udt_cell = Output.new(
        capacity: capacity.to_s,
        data: data + signature,
        lock: wallet.lock,
        type: token_info.type
      )
      min_capacity = udt_cell.calculate_min_capacity
      if capacity < min_capacity
        raise "Capacity is not enough to hold the whole cell, minimal capacity: #{min_capacity}"
      end

      outputs = [udt_cell]
      if input_capacities > capacity
        outputs << Output.new(
          capacity: (input_capacities - capacity).to_s,
          data: '',
          lock: lock
        )
      end
      tx = Transaction.new(
        version: 0,
        deps: [api.mruby_out_point],
        inputs: i.inputs,
        outputs: outputs
      ).sign_sighash_all_inputs(@key)
      hash = api.send_transaction(tx)
      OpenStruct.new(tx_hash: hash, token_info: token_info)
    end

    # @param token_info [Udt::TokenInfo | Udt::FixedAmountTokenInfo]
    def udt_wallet(token_info)
      Udt::Wallet.new(api, @key.privkey, token_info)
    end

    # @param token_info [Udt::TokenInfo | Udt::FixedAmountTokenInfo]
    def udt_account_wallet(token_info)
      Ckb::Udt::AccountWallet.new(api, @key.privkey, token_info)
    end

    private

    # @param token_name [String]
    # @param account_wallet [Boolean]
    #
    # @return [Udt::TokenInfo]
    def created_token_info(token_name, account_wallet: false)
      Udt::TokenInfo.new(api, token_name, @key.pubkey, account_wallet)
    end

    # @param capacity [Integer]
    # @param min_capacity [Integer]
    def gather_inputs(capacity, min_capacity)
      if capacity < min_capacity
        raise "capacity cannot be less than #{min_capacity}"
      end

      input_capacities = 0
      inputs = []
      get_unspent_cells.each do |cell|
        input = Input.new(
          previous_output: OutPoint.new(
            tx_hash: cell[:out_point][:tx_hash],
            index: cell[:out_point][:index]
          ),
          args: [@key.pubkey],
          since: '0'
        )
        inputs << input
        input_capacities += cell[:capacity].to_i
        if input_capacities >= capacity && (input_capacities - capacity) >= min_capacity
          break
        end
      end
      raise 'Not enough capacity!' if input_capacities < capacity

      OpenStruct.new(inputs: inputs, capacities: input_capacities)
    end

    def verify_script
      Script.new(
        code_hash: api.mruby_cell_hash,
        args: [
          VERIFY_SCRIPT,
          # We could of course just hash raw bytes, but since right now CKB
          # CLI already uses this scheme, we stick to the same way for compatibility
          @key.pubkey_hash
        ]
      )
    end

    def verify_script_hash
      verify_script.to_hash
    end
  end
end
