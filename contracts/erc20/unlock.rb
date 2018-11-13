if ARGV.length < 3
  raise "Not enough arguments!"
end

tx = CKB.load_tx
sha3 = Sha3.new

ARGV.drop(2).each do |argument|
  sha3.update(argument)
end

# TODO: hash all unlock and contract script hashes

# hash_indices is passed in as a string of format "1,2|3,4|5", this means
# hash index 1 and 2 of inputs, index 3 and 4 of outputs, and index 5 of
# deps. All indices here are 0-based.
hash_indices = ARGV[2].split("|").map { |s| s.split(",") }
hash_indices[0].each do |input_index|
  input = tx["inputs"][input_index]
  sha3.update(input["hash"])
  sha3.update(input["index"].to_s)
  sha3.update(input["unlock"]["version"].to_s)
  # First argument here is signature
  input["unlock"]["arguments"].drop(1).each do |argument|
    sha3.update(argument)
  end
end
hash_indices[1].each do |output_index|
  output = tx["outputs"][output_index]
  sha3.update(output["capacity"].to_s)
  sha3.update(output["lock"])
end
hash_indices[2].each do |dep_index|
  dep = tx["deps"][dep_index]
  sha3.update(dep["hash"])
  sha3.update(dep["index"].to_s)
end
hash = sha3.final

pubkey = ARGV[0]
signature = ARGV[1]

unless Secp256k1.verify(hex_to_bin(pubkey), hex_to_bin(signature), hash)
  raise "Signature verification error!"
end
