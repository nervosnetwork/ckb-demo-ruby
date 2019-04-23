# frozen_string_literal: true

require_relative 'token_info'
require_relative 'fixed_amount_token_info'
require_relative 'base_wallet'
require_relative 'wallet'
require_relative 'account_wallet'

module Ckb
  module Udt
    UNLOCK_SCRIPT = File.read(File.expand_path('../../../scripts/udt/unlock.rb', __dir__))
    UNLOCK_SINGLE_CELL_SCRIPT = File.read(File.expand_path('../../../scripts/udt/unlock_single_cell.rb', __dir__))
    CONTRACT_SCRIPT = File.read(File.expand_path('../../../scripts/udt/contract.rb', __dir__))
    FIXED_AMOUNT_GENESIS_UNLOCK_SCRIPT = File.read(File.expand_path('../../../scripts/fixed_amount_udt/genesis_unlock.rb', __dir__))
    FIXED_AMOUNT_CONTRACT_SCRIPT = File.read(File.expand_path('../../../scripts/fixed_amount_udt/contract.rb', __dir__))
  end
end
