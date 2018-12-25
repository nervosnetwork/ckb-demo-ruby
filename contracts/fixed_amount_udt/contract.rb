# This contract needs following signed arguments:
# 0. hash of all inputs in bootstrap tx. By including this field here, different
# bootstrapping phases would generate contracts with different type hash, hence
# preventing the problem when token creator executes more than one token creation
# process, ensuring that we can create a token with a fixed upper limit.
# 1. pubkey, used to identify token owner
#
# This contract might also need 1 optional unsigned argument:
# 2. (optional) bootstrap signature, this is only used in the initial bootstrap
# phase to bypass sum verification. The signature would be like a SIGHASH_ALL
# operation to avoid replay attack.
if ARGV.length != 2 && ARGV.length != 3
  raise "Not enough arguments!"
end

def hex_to_bin(s)
  if s.start_with?("0x")
    s = s[2..-1]
  end
  s.each_char.each_slice(2).map(&:join).map(&:hex).map(&:chr).join
end

contract_type_hash = CKB.load_script_hash(0, CKB::Source::CURRENT, CKB::Category::TYPE)

tx = CKB.load_tx

if ARGV.length == 3
  message_sha3 = Sha3.new
  tx["inputs"].each_with_index do |input, i|
    message_sha3.update(input["hash"])
    message_sha3.update(input["index"].to_s)
    message_sha3.update(CKB.load_script_hash(i, CKB::Source::INPUT, CKB::Category::LOCK))
  end
  if hex_to_bin(ARGV[0]) != message_sha3.final
    raise "Input hash is incorrect!"
  end

  sha3 = Sha3.new
  # Contract type hash already encodes all signed arguments here
  sha3.update(contract_type_hash)
  tx["inputs"].each_with_index do |input, i|
    sha3.update(input["hash"])
    sha3.update(input["index"].to_s)
    sha3.update(CKB.load_script_hash(i, CKB::Source::INPUT, CKB::Category::LOCK))
    hash = CKB.load_script_hash(i, CKB::Source::INPUT, CKB::Category::TYPE)
    if hash == contract_type_hash
      sha3.update(CKB::CellField.new(CKB::Source::INPUT, i, CKB::CellField::DATA).read(0, 8))
    end
  end
  tx["outputs"].each_with_index do |output, i|
    sha3.update(output["capacity"].to_s)
    sha3.update(output["lock"])
    hash = CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::TYPE)
    if hash
      sha3.update(hash)
      if hash == contract_type_hash
        sha3.update(CKB::CellField.new(CKB::Source::OUTPUT, i, CKB::CellField::DATA).read(0, 8))
      end
    end
  end

  data = sha3.final

  unless Secp256k1.verify(hex_to_bin(ARGV[1]), hex_to_bin(ARGV[2]), data)
    raise "Signature verification error!"
  end
  return
end

input_sum = tx["inputs"].size.times.map do |i|
  if CKB.load_script_hash(i, CKB::Source::INPUT, CKB::Category::TYPE) == contract_type_hash
    CKB::CellField.new(CKB::Source::INPUT, i, CKB::CellField::DATA).read(0, 8).unpack("Q<")[0]
  else
    0
  end
end.reduce(&:+)

output_sum = tx["outputs"].size.times.map do |i|
  if CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::TYPE) == contract_type_hash
    CKB::CellField.new(CKB::Source::OUTPUT, i, CKB::CellField::DATA).read(0, 8).unpack("Q<")[0]
  else
    0
  end
end.reduce(&:+)

if input_sum != output_sum
  raise "Sum verification failed!"
end
