# This contract needs 1 signed arguments:
# 1. pubkey, used to identify token owner
# This contracts also accepts one unsigned argument:
# 2. signature, signature used to present ownership
if ARGV.length != 2
  raise "Wrong number of arguments!"
end

def hex_to_bin(s)
  if s.start_with?("0x")
    s = s[2..-1]
  end
  [s].pack("H*")
end

tx = CKB.load_tx
sha3 = Sha3.new

out_point = CKB.load_input_out_point(0, CKB::Source::CURRENT)
sha3.update(out_point["hash"])
sha3.update(out_point["index"].to_s)
sha3.update(CKB::CellField.new(CKB::Source::CURRENT, 0, CKB::CellField::LOCK_HASH).readall)
hash = sha3.final

pubkey = ARGV[0]
signature = ARGV[1]

unless Secp256k1.verify(hex_to_bin(pubkey), hex_to_bin(signature), hash)
  raise "Signature verification error!"
end
