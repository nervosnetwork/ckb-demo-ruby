# This contract needs 1 signed arguments:
# 1. pubkey, used to identify token owner
# This contracts also accepts one unsigned argument:
# 2. signature, signature used to present ownership
# 3. index, an integer denoting the index of output to be signed.
# It's up to transaction assembler to arrange outputs, this script
# only cares that correct data are signed.
if ARGV.length != 3
  raise "Wrong number of arguments!"
end

def hex_to_bin(s)
  if s.start_with?("0x")
    s = s[2..-1]
  end
  s.each_char.each_slice(2).map(&:join).map(&:hex).map(&:chr).join
end

tx = CKB.load_tx
sha3 = Sha3.new

outpoint = CKB.load_input_out_point(0, CKB::Source::CURRENT)
sha3.update(outpoint["hash"])
sha3.update(outpoint["index"].to_s)
sha3.update(CKB::CellField.new(CKB::Source::CURRENT, 0, CKB::CellField::LOCK_HASH).readall)
output_index = ARGV[2].to_i
output = tx["outputs"][output_index]
sha3.update(output["capacity"].to_s)
sha3.update(output["lock"])
if hash = CKB.load_script_hash(output_index, CKB::Source::OUTPUT, CKB::Category::CONTRACT)
  sha3.update(hash)
end

hash = sha3.final

pubkey = ARGV[0]
signature = ARGV[1]

unless Secp256k1.verify(hex_to_bin(pubkey), hex_to_bin(signature), hash)
  raise "Signature verification error!"
end
