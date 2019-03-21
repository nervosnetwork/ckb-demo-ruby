# Introduction

This document explains how to write new scripts for CKB.

# Transaction Model

Below is an example of CKB's transaction:

![Transaction Model](/docs/images/tx.png)

Note that to focus on explaining script model, certain fields in a cell(such as cell data) are omitted here for simplicity reason.

In CKB, each cell has 2 associated scripts:

* A required lock script, note cell usually only keeps the hash of the lock script, we will explain this later. This is used to verify *who* can unlock the cell, for example, we can put secp256k1 verification in lock script to verify a signature is indeed signed by the cell owner, and only unlock the cell when the signature is valid.
* An optional type script. This is used to verify *how* one can use the cell, for example, type script can be used to ensure that no new tokens are created out from the air when transferring user-defined tokens.

When unlocking a cell in a transaction, the corresponding input part should contain an unlock script, the hash of the unlock script should match `lock` part in the referenced cell(in other words, we are using `P2SH` scheme here). So another way of looking at this problem here, is that it's the `lock` part in the cell that really determines what unlock script is used here, and we can treat `lock` and `unlock` here as the same thing.

In addition to the different use cases, lock script and type script are also executed in different time: lock script is executed when we are *unlocking* a cell, while type script is executed when we are *creating* a cell. When validating the transaction in the above example, we are only executing `Lock 1`, `Lock 2`, `Type 3` and `Type 4` here.

## Script Model

Both lock and type scripts are represented using the [Script](https://github.com/nervosnetwork/ckb/blob/3abf2b1f43dd27e986c8b2ee311d91e896051d3a/protocol/src/protocol.fbs#L85-L91) model. Fields in this model include:

* `version`: version field used to resolve incompatible upgrades.
* `binary`: ELF formatted binary containing the actual RISC-V based script
* `reference`: if your script already exists on CKB, you can use this field to *reference* the script instead of including it again. You can just put the script hash(will explain later how this is calculated) in this `reference ` field, then list the cell containing the script as a dep in current transaction. CKB would automatically locate cell, load the binary from there and use it as script `binary` part. Notice this only works when you don't provide a `binary` field value, otherwise the value in `binary` field always take precedence.
* `signed_args`: Signed arguments, we will explain later what they are and how to distinguish them from `args`
* `args`: Normal arguments

CKB scripts use UNIX standard execution environment. Each script binary should contain a main function with the following signature:

```c
int main(int argc, char* argv[]);
```

CKB will concat `signed_args` and `args`, then use the concatenated array to fill `argc`/`argv` part, then start the script execution. Upon termination, the executed `main` function here will provide a return code, `0` means the script execution succeeds, other values mean the execution fails.

`signed_args` is introduced here to enable script sharing: assume 2 CKB users both want to use secp256k1 algorithm to secure their cells, in order to do this, they will need scripts for secp256k1 verification, the scripts will also need to include their public key respectively. If they put public key directly in the script binary, the difference in public keys will lead to different script binaries, which is quite a waste of resource considering the majority part of the 2 scripts here is exactly the same. To solve this problem, they can each put their public key in `signed_args` part of the script model, then leverage the same secp256k1 script binary. This way they can save as much resource as they can while preserving different ownerships. This might not be a huge save when we are talking 2 users, but as the number of users grow, the resource we can save with this scheme is huge.

Each script has a `type hash` which uniquely identifies the script, for example, the `type hash` of unlock script, is exactly the corresponding `lock` field value in the referenced cell. When calculating type hash for a script, `version`, `binary`, `reference` and `signed_args` will all be used. So another way of looking at `signed_args`, is that it really is a part of the script.

In practice, one example script might look like following:

```json
{
  "version": 0,
  "reference": "0x12b464bcab8f55822501cdb91ea35ea707d72ec970363972388a0c49b94d377c",
  "signed_args": [
    "024a501efd328e062c8675f2365970728c859c592beeefd6be8ead3d901330bc01"
  ],
  "args": [
    "3044022038f282cffdd26e2a050d7779ddc29be81a7e2f8a73706d2b7a6fde8a78e950ee0220538657b4c01be3e77827a82e92d33a923e864c55b88fd18cd5e5b25597432e9b",
    "1"
  ]
}
```

This script uses `reference` field to refer to an existing cell for script binary. It contains one `signed_args` item, which is the public key for current user. It also has 2 items for `args`: the signature calculated for current transaction, and the sighash type to use here. Note that while this example has one `signed_args` item and 2 `args` items, this is completely determined by the actual script binary running, CKB doesn't have any restrictions here.

# Writing Scripts in Ruby

While it is possible to write scripts in pure C, it is not the main focus of this document. Here we will explain how to write Ruby scripts with our custom [mruby-contracts](https://github.com/nervosnetwork/mruby-contracts). Note this just serves as an example here, it doesn't mean CKB is limited to scripts written in Ruby. On the contrary, CKB is extremely flexible and you can use almost any languages out there to write scripts, for example, you can leverage [micropython](https://micropython.org/) to write Python scripts, you can use [duktape](https://duktape.org/) to build JavaScript scripts. Of course if your focus is on performance, you can also directly use C to write scripts that extracts the maximum computing power out of CKB VM, and when Rust's RISC-V port becomes more stable, you can also use Rust to write CKB scripts.

To help writing CKB scripts, we have ported [mruby](https://github.com/mruby/mruby) to CKB VM environment and also created several mruby libraries supporting CKB script development:

* mruby-blake2b: A blake2b binding for mruby environment(hard-code personalization to "ckb-default-hash")
* mruby-secp256k1: A secp256k1 binding for mruby environment
* mruby-ckb: CKB supporting libraries, including features to read transaction data as well as sending debug messages.

To build `mruby-contracts`, first follow the [setup steps](https://github.com/nervosnetwork/ckb-demo-ruby-sdk#configure-ckb) in the Ruby SDK. Then you can locate the mruby script cell via the Ruby SDK:

```ruby
[1] pry(main)> api = Ckb::Api.new
[2] pry(main)> api.mruby_cell_hash
[3] pry(main)> api.mruby_out_point
```

`mruby_cell_hash` should be used as `reference` field in the script you assembled. `mruby_out_point` should go in the deps part of the transaction you assembled. With that, you can put the Ruby script you want to run as the first signed argument in the script:

```json
{
  "version": 0,
  "reference": "0x12b464bcab8f55822501cdb91ea35ea707d72ec970363972388a0c49b94d377c",
  "signed_args": [
    "# This contract needs 1 signed arguments:\n# 0. pubkey, used to identify token owner\n# This contracts also accepts 2 required unsigned arguments and 1\n# optional unsigned argument:\n# 1. signature, signature used to present ownership\n# 2. type, SIGHASH type\n# 3. output(s), this is only used for SIGHASH_SINGLE and SIGHASH_MULTIPLE types,\n# for SIGHASH_SINGLE, it stores an integer denoting the index of output to be\n# signed; for SIGHASH_MULTIPLE, it stores a string of `,` separated array denoting\n# outputs to sign\nif ARGV.length != 3 && ARGV.length != 4\n  raise \"Wrong number of arguments!\"\nend\n\nSIGHASH_ALL = 0x1\nSIGHASH_NONE = 0x2\nSIGHASH_SINGLE = 0x3\nSIGHASH_MULTIPLE = 0x4\nSIGHASH_ANYONECANPAY = 0x80\n\ndef hex_to_bin(s)\n  if s.start_with?(\"0x\")\n    s = s[2..-1]\n  end\n  [s].pack(\"H*\")\nend\n\n\ntx = CKB.load_tx\nblake2b = Blake2b.new\n\nblake2b.update(ARGV[2])\nsighash_type = ARGV[2].to_i\n\nif sighash_type & SIGHASH_ANYONECANPAY != 0\n  # Only hash current input\n  out_point = CKB.load_input_out_point(0, CKB::Source::CURRENT)\n  blake2b.update(out_point[\"hash\"])\n  blake2b.update(out_point[\"index\"].to_s)\n  blake2b.update(CKB::CellField.new(CKB::Source::CURRENT, 0, CKB::CellField::LOCK_HASH).readall)\nelse\n  # Hash all inputs\n  tx[\"inputs\"].each_with_index do |input, i|\n    blake2b.update(input[\"hash\"])\n    blake2b.update(input[\"index\"].to_s)\n    blake2b.update(CKB.load_script_hash(i, CKB::Source::INPUT, CKB::Category::LOCK))\n  end\nend\n\ncase sighash_type & (~SIGHASH_ANYONECANPAY)\nwhen SIGHASH_ALL\n  tx[\"outputs\"].each_with_index do |output, i|\n    blake2b.update(output[\"capacity\"].to_s)\n    blake2b.update(output[\"lock\"])\n    if hash = CKB.load_script_hash(i, CKB::Source::OUTPUT, CKB::Category::TYPE)\n      blake2b.update(hash)\n    end\n  end\nwhen SIGHASH_SINGLE\n  raise \"Not enough arguments\" unless ARGV[3]\n  output_index = ARGV[3].to_i\n  output = tx[\"outputs\"][output_index]\n  blake2b.update(output[\"capacity\"].to_s)\n  blake2b.update(output[\"lock\"])\n  if hash = CKB.load_script_hash(output_index, CKB::Source::OUTPUT, CKB::Category::TYPE)\n    blake2b.update(hash)\n  end\nwhen SIGHASH_MULTIPLE\n  raise \"Not enough arguments\" unless ARGV[3]\n  ARGV[3].split(\",\").each do |output_index|\n    output_index = output_index.to_i\n    output = tx[\"outputs\"][output_index]\n    blake2b.update(output[\"capacity\"].to_s)\n    blake2b.update(output[\"lock\"])\n    if hash = CKB.load_script_hash(output_index, CKB::Source::OUTPUT, CKB::Category::TYPE)\n      blake2b.update(hash)\n    end\n  end\nend\nhash = blake2b.final\n\npubkey = ARGV[0]\nsignature = ARGV[1]\n\nunless Secp256k1.verify(hex_to_bin(pubkey), hex_to_bin(signature), hash)\n  raise \"Signature verification error!\"\nend\n",
    "024a501efd328e062c8675f2365970728c859c592beeefd6be8ead3d901330bc01"
  ],
  "args": [
    "3044022038f282cffdd26e2a050d7779ddc29be81a7e2f8a73706d2b7a6fde8a78e950ee0220538657b4c01be3e77827a82e92d33a923e864c55b88fd18cd5e5b25597432e9b",
    "1"
  ]
}
```

As you can see, the first argument of `signed_args` here is just a Ruby script, with this, CKB will then first load mruby, and run your Ruby script as the actual script. If this script throws an exception, it will be translated to non-zero return code, denoting script execution error. If the script runs without exception, the script will be considered success.

## Ruby Libraries

Even though Ruby is a powerful language, it cannot fulfill all the tasks without supporting libraries, we also provide a series of Ruby libraries helping writing scripts.

### mruby-blake2b

[mruby-blake2b](https://github.com/nervosnetwork/mruby-contracts/tree/master/mruby-blake2b) is just a simple library providing Ruby bindings for blake2b(hard-code personalization to "ckb-default-hash"). The usage is as follows:

```ruby
blake2b = Blake2b.new
blake2b.update("abcdef")
# Only string is accepted as argument to the update method
blake2b.update(5.to_s)
hash = blake2b.final
```

### mruby-secp256k1

[mruby-secp256k1](https://github.com/nervosnetwork/mruby-contracts/tree/master/mruby-secp256k1) provides Ruby binding for secp256k1 algorithm. It provides the following APIs:

#### Fetch public key

```ruby
secret_key = "<I am a secret key>"
public_key = Secp256k1.pubkey(secret_key)
```

#### Sign message

```ruby
secret_key = "<I am a secret key>"
message = "<I am a 32 byte long message>"
signature = Secp256k1.sign(secret_key, message)
```

### Verify signature

```ruby
public_key = "<I am a public key>"
signature = "<I am a signature>"
message = "<I am a 32 byte long message>"
verified = Secp256k1.verify(public_key, signature, message)
unless verified
  raise "Signature verification error!"
end
```

### mruby-ckb

[mruby-ckb](https://github.com/nervosnetwork/mruby-contracts/tree/master/mruby-ckb) provides wrapper functions to interact with CKB.

#### Debug

First mruby-ckb provides a debug method to print debug messages to CKB:

```ruby
CKB.debug "I'm a debug message: ${5}"
```

#### Load Transaction

If we have the following snippet in a Ruby script:

```ruby
tx = CKB.load_tx
CKB.debug "TX: #{tx}"
```

We can then expect logs in CKB like following:

```
2018-12-17 16:03:21.650 +08:00 TransactionPoolService DEBUG script  Transaction 5c065df07094..(omit 40)..5bcdebf47e81, input 0 DEBUG OUTPUT: TX: {"version"=>0, "deps"=>[{"hash"=>"s+\xfdV\xf4v\x87\x05cm{J\x1dc\xbc\x01]\xff\xaf)\x8e!\xe2@Gx\xb5!\xc3\x17]\xca", "index"=>2}], "inputs"=>[{"hash"=>"d\x02\x11\v\x8f\eT\xe6\xce\xe9\xcej\x82\xf9_K\x97U\f\xe1\x92\xfe\xb2\xba_\x86\xe6\x90\xb5PW\xc5", "index"=>0}], "outputs"=>[{"capacity"=>35000, "lock"=>"\xfe\x1a\xc2\xd4\xa6\xd8R\xc3\x94t>\x98\x8f\xd2\xcf\x9eI\xa7j%5n|\x8b\#@\xf6X\xef\xbc,\x1f"}, {"capacity"=>15000, "lock"=>"\x98L\xb0\xc6\a\xe5\xfa7\x8fj\x85m\x02\xdf\x82Y\x0e\xf8T\xc6\xa2>\x15\xd2\f\xe5\xda\x9f\xa4\x9d\x8f\xb2"}]}
```

Here we can see the overall transaction structure is returned by `CKB.load_tx`

#### Load Script Hash

Following code can be used to load script hash:

```ruby
# Load cell input 1's unlock script hash, note lock and unlock refer to the same item.
# Return value here is a string of 32 bytes
CKB.load_script_hash(1, CKB::Source::INPUT, CKB::Category::LOCK)
# Load cell output 2's type script hash, note that type script is optional, so the
# returned value here could be nil
CKB.load_script_hash(2, CKB::Source::OUTPUT, CKB::Category::TYPE)
# Load current cell's lock hash
CKB.load_script_hash(0, CKB::Source::CURRENT, CKB::Category::LOCK)
```

#### Load Input OutPoint

If we have the following snippet in a Ruby script:

```ruby
CKB.debug "OutPoint: #{CKB.load_input_out_point(0, CKB::Source::CURRENT)}"
```

We can then expect logs in CKB like following:

```
2018-12-17 16:10:44.185 +08:00 TransactionPoolService DEBUG script  Transaction f424348ef9d0..(omit 40)..8f79d68c82b4, input 0 DEBUG OUTPUT: OutPoint: {"hash"=>"#~\x9ekK23\xc7\x0f%\xaa\n\xa1\xc8\xc0\x81<\x948`B\xab\x9e\xb5\xe0\xea8\xe3r\xd3\x9e\x99", "index"=>0}
```

It's also possible to load input OutPoint from different index:

```ruby
CKB.load_input_out_point(1, CKB::Source::INPUT)
# This won't trigger errors but would always return nil since output doesn't have
# OutPoint
CKB.load_input_out_point(1, CKB::Source::OUTPUT)
```

#### Load Cell By Field

We can also load certain field in a cell:

```ruby
# Capacity is serialized into 8-byte little endian bytes
capacity = CKB::CellField.new(CKB::Source::INPUT, 1, CKB::CellField::CAPACITY).read(0, 8).unpack("Q<")[0]
# Data is stored as raw bytes, readall here can be used to fetch all the data
data = CKB::CellField.new(CKB::Source::OUTPUT, 2, CKB::CellField::DATA).readall
# Lock and contract hash are returned as 32 byte string
lock_hash_length = CKB::CellField.new(CKB::Source::CURRENT, 0, CKB::CellField::LOCK_HASH).length
unless length == 32
  raise "Lock hash has invalid length!"
end
contract_hash = CKB::CellField.new(CKB::Source::OUTPUT, 0, CKB::CellField::LOCK_HASH).read(16, 16)
```
