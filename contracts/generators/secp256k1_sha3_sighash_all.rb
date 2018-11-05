if ARGV.length < 1
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

def hex_to_bin(s)
  s.each_char.each_slice(2).map(&:join).map(&:hex).map(&:chr).join
end

def bin_to_hex(s)
  s.bytes.map { |b| b.to_s(16).rjust(2, "0") }.join
end

seckey = hex_to_bin(ARGV[0])
pubkey = Secp256k1.pubkey(seckey)
CKB.debug "Pubkey: #{bin_to_hex(pubkey)}"

signature = Secp256k1.sign(seckey, hash)
CKB.debug "Signature: #{bin_to_hex(signature)}"
