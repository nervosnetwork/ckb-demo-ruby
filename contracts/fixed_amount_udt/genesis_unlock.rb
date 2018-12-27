# This contract needs following signed arguments:
# 0. rate, used to tell how many tokens can 1 CKB capacity exchange.
# 1. lock hash, used to receive capacity in ICO phase
# 2. pubkey, used to identify token owner
#
# This contracts also 3 optional unsigned arguments:
# 3. signature, signature used to present ownership
# 4. type, SIGHASH type
# 5. output(s), this is only used for SIGHASH_SINGLE and SIGHASH_MULTIPLE types,
# for SIGHASH_SINGLE, it stores an integer denoting the index of output to be
# signed; for SIGHASH_MULTIPLE, it stores a string of `,` separated array denoting
# outputs to sign
# If they exist, we will do the proper signature verification way, if not
# we will check and perform an ICO step using rate.
if ARGV.length != 3 && ARGV.length != 5 && ARGV.length != 6
  raise "Wrong number of arguments!"
end

SIGHASH_ALL = 0x1
SIGHASH_NONE = 0x2
SIGHASH_SINGLE = 0x3
SIGHASH_MULTIPLE = 0x4
SIGHASH_ANYONECANPAY = 0x80

def hex_to_bin(s)
  if s.start_with?("0x")
    s = s[2..-1]
  end
  s.each_char.each_slice(2).map(&:join).map(&:hex).map(&:chr).join
end

tx = CKB.load_tx

if ARGV.length >= 5
  sha3 = Sha3.new
  ARGV.drop(4).each do |argument|
    sha3.update(argument)
  end
  sighash_type = ARGV[4].to_i

  if sighash_type & SIGHASH_ANYONECANPAY != 0
    # Only hash current input
    outpoint = CKB.load_input_out_point(0, CKB::Source::CURRENT)
    sha3.update(outpoint["hash"])
    sha3.update(outpoint["index"].to_s)
    sha3.update(CKB::CellField.new(CKB::Source::CURRENT, 0, CKB::CellField::LOCK_HASH).readall)
  else
    # Hash all inputs
    tx["inputs"].each_with_index do |input, i|
      sha3.update(input["hash"])
      sha3.update(input["index"].to_s)
      sha3.update(CKB.load_script_hash(i, CKB::Source::INPUT, CKB::Category::LOCK))
    end
  end

  case sighash_type & (~SIGHASH_ANYONECANPAY)
  when SIGHASH_ALL
    tx["outputs"].each_with_index do |output, i|
      sha3.update(output["capacity"].to_s)
      sha3.update(output["lock"])
      if hash = CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::TYPE)
        sha3.update(hash)
      end
    end
  when SIGHASH_SINGLE
    raise "Not enough arguments" unless ARGV[5]
    output_index = ARGV[5].to_i
    output = tx["outputs"][output_index]
    sha3.update(output["capacity"].to_s)
    sha3.update(output["lock"])
    if hash = CKB.load_script_hash(output_index, CKB::Source::OUTPUT, CKB::Category::TYPE)
      sha3.update(hash)
    end
  when SIGHASH_MULTIPLE
    raise "Not enough arguments" unless ARGV[5]
    ARGV[5].split(",").each do |output_index|
      output_index = output_index.to_i
      output = tx["outputs"][output_index]
      sha3.update(output["capacity"].to_s)
      sha3.update(output["lock"])
      if hash = CKB.load_script_hash(output_index, CKB::Source::OUTPUT, CKB::Category::TYPE)
        sha3.update(hash)
      end
    end
  end
  hash = sha3.final

  pubkey = ARGV[2]
  signature = ARGV[3]

  unless Secp256k1.verify(hex_to_bin(pubkey), hex_to_bin(signature), hash)
    raise "Signature verification error!"
  end
  return
end

contract_type_hash = CKB.load_script_hash(0, CKB::Source::CURRENT, CKB::Category::TYPE)

# First, we test there's at least one output that has current UDT contract, so the
# cell contract validator code can take place
has_udt_output = tx["outputs"].length.times.any? do |i|
  CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::TYPE) == contract_type_hash
end
unless has_udt_output
  raise "There must at least be one contract output!"
end

# Next we test that there's one output cell transformed from current cell.
current_input_lock = CKB.load_script_hash(0, CKB::Source::CURRENT, CKB::Category::LOCK)
current_input_capacity = CKB::CellField.new(CKB::Source::CURRENT, 0, CKB::CellField::CAPACITY).readall.unpack("Q<")[0]

current_output_index = tx["outputs"].length.times.find do |i|
  lock = CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::LOCK)
  type = CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::TYPE)
  capacity = tx["outputs"][i]["capacity"]

  lock == current_input_lock &&
    type == contract_type_hash &&
    capacity == current_input_capacity
end
unless current_output_index
  raise "Cannot find corresponding output cell for current input!"
end

# Finally, we test that in exchange for tokens, the sender has paid enough capacity
# in a new empty cell.
paid_output_index = tx["outputs"].length.times.find do |i|
  CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::LOCK) == hex_to_bin(ARGV[1])
end
unless paid_output_index
  raise "Cannot find paid output!"
end
if CKB::CellField.new(CKB::Source::OUTPUT, paid_output_index, CKB::CellField::DATA).length > 0
  raise "Not an empty cell!"
end
if CKB::CellField.new(CKB::Source::OUTPUT, paid_output_index, CKB::CellField::TYPE).exists?
  raise "Not an empty cell!"
end
input_tokens = CKB::CellField.new(CKB::Source::CURRENT, 0, CKB::CellField::DATA).read(0, 8).unpack("Q<")[0]
output_tokens = CKB::CellField.new(CKB::Source::OUTPUT, current_output_index, CKB::CellField::DATA).read(0, 8).unpack("Q<")[0]
rate = ARGV[0].to_i
required_capacity = (input_tokens - output_tokens + rate - 1) / rate
paid_output = tx["outputs"][paid_output_index]
if paid_output["capacity"] != required_capacity
  raise "Paid capacity is wrong!"
end
