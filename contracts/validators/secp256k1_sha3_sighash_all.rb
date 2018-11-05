if ARGV.length < 2
  raise "Not enough arguments!"
end

tx = CKB.load_tx
sha3 = Sha3.new

sha3.update(tx["version"].to_s)
tx["deps"].each do |dep|
  sha3.update(dep["hash"])
  sha3.update(dep["index"].to_s)
end
tx["inputs"].each do |input|
  sha3.update(input["hash"])
  sha3.update(input["index"].to_s)
  sha3.update(input["unlock"]["version"].to_s)
  # First argument here is signature
  input["unlock"]["arguments"].drop(1).each do |argument|
    sha3.update(argument)
  end
end
tx["outputs"].each do |output|
  sha3.update(output["capacity"].to_s)
  sha3.update(output["lock"])
end
hash = sha3.final

pubkey = ARGV[0]
signature = ARGV[1]

def hex_to_bin(s)
  s.each_char.each_slice(2).map(&:join).map(&:hex).map(&:chr).join
end

unless Secp256k1.verify(hex_to_bin(pubkey), hex_to_bin(signature), hash)
  raise "Signature verification error!"
end
