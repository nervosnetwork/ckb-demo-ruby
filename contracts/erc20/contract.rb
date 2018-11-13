if ARGV.length < 2
  raise "Not enough arguments!"
end

def hex_to_bin(s)
  s.each_char.each_slice(2).map(&:join).map(&:hex).map(&:chr).join
end

contract_type_hash = hex_to_bin(ARGV[1])

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
if ARGV.length >= 3
  sha3 = Sha3.new
  sha3.update(contract_type_hash)
  tx["inputs"].each_with_index do |input, i|
    if CKB.load_script_hash(i, CKB::INPUT, CKB::CONTRACT) == contract_type_hash
      sha3.update(CKB::Cell.new(CKB::INPUT, i).read(0, 8))
    end
  end
  tx["outputs"].each_with_index do |output, i|
    if CKB.load_script_hash(i, CKB::OUTPUT, CKB::CONTRACT) == contract_type_hash
      sha3.update(CKB::Cell.new(CKB::OUTPUT, i).read(0, 8))
    end
  end

  unless Secp256k1.verify(hex_to_bin(ARGV[0]), hex_to_bin(ARGV[2]), sha3.final)
    raise "Signature verification error!"
  end
  supermode = true
end

input_sum = tx["inputs"].size.times.map do |i|
  if CKB.load_script_hash(i, CKB::INPUT, CKB::CONTRACT) == contract_type_hash
    CKB::Cell.new(CKB::INPUT, i).read(0, 8).unpack("Q<")[0]
  else
    0
  end
end.sum

output_sum = tx["outputs"].size.times.map do |i|
  if CKB.load_script_hash(i, CKB::OUTPUT, CKB::CONTRACT) == contract_type_hash
    CKB::Cell.new(CKB::OUTPUT, i).read(0, 8).unpack("Q<")[0]
  else
    0
  end
end

# This contract here allows destroying tokens, a different contract might
# choose to forbid this.
if (!supermode) && input_sum < output_sum
  raise "Sum verification failed!"
end
