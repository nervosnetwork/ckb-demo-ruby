# This contract needs 2 signed arguments:
# 1. token name, this is just a placeholder to distinguish between tokens,
# it will not be used in the actual contract. The pair of token name and
# pubkey uniquely identifies a token.
# 2. pubkey, used to perform supermode operations such as issuing new tokens
# This contract also needs 1 or 2 unsigned arguments:
# 3. Current contract type hash, will be verified in unlock contract
# 4. (optional) supermode signature, when present and verified, the transaction
# can perform super mode operations
if ARGV.length < 3
  raise "Not enough arguments!"
end

def hex_to_bin(s)
  if s.start_with?("0x")
    s = s[2..-1]
  end
  s.each_char.each_slice(2).map(&:join).map(&:hex).map(&:chr).join
end

contract_type_hash = hex_to_bin(ARGV[2])

tx = CKB.load_tx

supermode = false
# There are 2 ways to execute this contract:
# * Normal user can run the contract with only contract hash attached
# as an argument, this will ensure the contract to run sum verification
# * For superuser denoted via the pubkey from signed_args, they can
# also do more operations such as issuing more tokens. They can change
# the script to a special mode by attaching a signature signed from private
# key for the pubkey attached. With this signature, they will be able to
# add more tokens.
if ARGV.length >= 4
  sha3 = Sha3.new
  sha3.update(contract_type_hash)
  tx["inputs"].each_with_index do |input, i|
    if CKB.load_script_hash(i, CKB::Source::INPUT, CKB::Category::CONTRACT) == contract_type_hash
      sha3.update(CKB::CellField.new(CKB::Source::INPUT, i, CKB::CellField::DATA).read(0, 8))
    end
  end
  tx["outputs"].each_with_index do |output, i|
    hash = CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::CONTRACT)
    if CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::CONTRACT) == contract_type_hash
      sha3.update(CKB::CellField.new(CKB::Source::OUTPUT, i, CKB::CellField::DATA).read(0, 8))
    end
  end

  data = sha3.final

  unless Secp256k1.verify(hex_to_bin(ARGV[1]), hex_to_bin(ARGV[3]), data)
    raise "Signature verification error!"
  end
  supermode = true
end

input_sum = tx["inputs"].size.times.map do |i|
  if CKB.load_script_hash(i, CKB::Source::INPUT, CKB::Category::CONTRACT) == contract_type_hash
    CKB::CellField.new(CKB::Source::INPUT, i, CKB::CellField::DATA).read(0, 8).unpack("Q<")[0]
  else
    0
  end
end.reduce(&:+)

output_sum = tx["outputs"].size.times.map do |i|
  if CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::CONTRACT) == contract_type_hash
    CKB::CellField.new(CKB::Source::OUTPUT, i, CKB::CellField::DATA).read(0, 8).unpack("Q<")[0]
  else
    0
  end
end.reduce(&:+)

# This contract here allows destroying tokens, a different contract might
# choose to forbid this.
if (!supermode) && input_sum < output_sum
  raise "Sum verification failed!"
end
