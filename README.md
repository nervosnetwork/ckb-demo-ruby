# How to use

## Prerequisites

First you will need to have [ckb](https://github.com/nervosnetwork/ckb) compiled of course. Feel free to just following the official build steps in the README. We will customize configs later.

You will also need [mruby-contracts](https://github.com/nervosnetwork/mruby-contracts). Follow the steps in the README to build it, you will need the generated mruby contract file at `build/argv_source_entry`.

## Configure CKB

Before we are using this SDK, we will need a customized CKB config for the following purposes:

* We will need a stable RPC port we can connect to.
* We will need to include mruby contract as a system cell. Notice it's also possible to create a new cell with mruby contract as the cell data, then referencing this cell later. Here for simplicity, we are sticking to a system cell.
* Depending on computing resource you have, you can also set CKB to dummy mining mode to save CPU resources. In dummy mode, CKB will randomly sleep for certain amount of time acting as a "mining" time instead of doing expensive calculations.

First you need a dummy folder to store all the configs, assuming we are using `/home/ubuntu/foo/bar`, we can do:

```bash
$ mkdir -p /home/ubuntu/foo/bar
$ cd /home/ubuntu/foo/bar
$ mkdir cells
$ cp <path to ckb>/spec/res/cells/* cells/
$ cp <path to mruby-contracts>/build/argv_source_entry cells/
```

In this newly created folder, create a file named `config.toml` with the following content:

```
[ckb]
chain = "/home/ubuntu/foo/bar/spec.yaml"

[logger]
filter = "info,chain=debug"

[rpc]
listen_addr = "0.0.0.0:3030"

[network]
boot_nodes = [
    "/ip4/47.75.42.29/tcp/12345/p2p/QmU6tySavbTF2uftZz1As2at4mxCr3QhhsFpfGpEbhBDiz"
]
reserved_nodes = []

[miner]
type_hash  = "0x70f11f57438ce880b4082dde77148fced17279cb3499d00ae21b73dc2971b566"
```

Notice the miner type hash here is the wallet address for the private key `e79f3207ea4980b7fed79956d5934249ceac4751a4fae01a0f7c4a96884bc4e3`.

Also, create a file named `spec.yaml` in the same folder with the following content:

```
name: "ckb"
genesis:
    seal:
        nonce: 0
        proof: [0]
    version: 0
    parent_hash: "0x0000000000000000000000000000000000000000000000000000000000000000"
    timestamp: 0
    txs_commit: "0x0000000000000000000000000000000000000000000000000000000000000000"
    txs_proposal: "0x0000000000000000000000000000000000000000000000000000000000000000"
    difficulty: "0x20000"
    cellbase_id: "0x0000000000000000000000000000000000000000000000000000000000000000"
    uncles_hash: "0x0000000000000000000000000000000000000000000000000000000000000000"
params:
    initial_block_reward: 50000
system_cells:
    # When loading dev.yaml, we will modify the path here to simplify loading,
    # but if you are copying this file elsewhere, you will need to provide full
    # path or relative path to where ckb is executing.
    - path: "/home/ubuntu/foo/bar/cells/verify"
    - path: "/home/ubuntu/foo/bar/cells/always_success"
    - path: "/home/ubuntu/foo/bar/cells/argv_source_entry"
pow:
    Dummy:
```

Remember if you are using a different directory than `/home/ubuntu/foo/bar`, you need to change the path in those 2 config files.

After all those changes, you should have the following directory structure:

```bash
$ tree
.
├── cells
│   ├── always_success
│   ├── argv_source_entry
│   └── verify
├── config.toml
└── spec.yaml

1 directory, 5 files
```

And you can try launching CKB using configs here:

```bash
./target/release/ckb run --data-dir=/home/ubuntu/foo/bar
```

Here release version of ckb is used, tho debug version will also work.

You can verify CKB is running by issuing RPC calls:

```bash
$ curl -d '{"id": 2, "jsonrpc": "2.0", "method":"get_tip_header","params": []}' -H 'content-type:application/json' 'http://localhost:3030'
{"jsonrpc":"2.0","result":{"raw":{"cellbase_id":"0xd56eab3c0fc9647fa3451a132cd967a4d4f1fc768b8a515ddbd46fb91d5a7a1f","difficulty":"0x20000","number":2,"parent_hash":"0x2726a2938313c5f920b46d224c9ef21e3c9aa3098e340116819680b88f585484","timestamp":1542609053701,"txs_commit":"0xd56eab3c0fc9647fa3451a132cd967a4d4f1fc768b8a515ddbd46fb91d5a7a1f","txs_proposal":"0x0000000000000000000000000000000000000000000000000000000000000000","uncles_count":0,"uncles_hash":"0x0000000000000000000000000000000000000000000000000000000000000000","version":0},"seal":{"nonce":5039870112347525463,"proof":[]}},"id":2}
```

## Running SDK

Now we can setup the Ruby SDK:

```bash
$ git clone https://github.com/nervosnetwork/ckb-demo-ruby-sdk
$ cd ckb-demo-ruby-sdk
$ bundle
$ bundle exec pry -r ./lib/ckb/wallet.rb
[1] pry(main)>
```

In the Ruby shell, we can start playing with the SDK.

### Basic wallet

```bash
[1] pry(main)> miner = Ckb::Wallet.from_hex(Ckb::Api.new, "e79f3207ea4980b7fed79956d5934249ceac4751a4fae01a0f7c4a96884bc4e3")
[2] pry(main)> alice = Ckb::Wallet.from_hex(Ckb::Api.new, "76e853efa8245389e33f6fe49dcbd359eb56be2f6c3594e12521d2a806d32156")
[3] pry(main)> miner.get_balance
=> 100000
[4] pry(main)> alice.get_balance
=> 0
[5] pry(main)> miner.send_capacity(alice.address, 12345)
=> "0xd7abc1407eb07d334fea86ef0e9b12b2273833137327c2a53f2d8ba1be1e4d85"
[6] pry(main)> # wait for some time
[7] pry(main)> alice.get_balance
=> 12345
[8] pry(main)> miner.get_balance
=> 337655
```

Notice miner's balance keeps growing with every new block.

### User defined coin

We can also create user defined coin that's separate from CKB. A new user defined coin is made of 2 parts:

* A coin name
* Coin's admin pubkey, only coin's admin can issue new coins. Other user can only transfer already created coins to others.

Ruby SDK here provides an easy way to create a coin from an existing wallet

```bash
[1] pry(main)> admin = Ckb::Wallet.from_hex(Ckb::Api.new, "e79f3207ea4980b7fed79956d5934249ceac4751a4fae01a0f7c4a96884bc4e3")
[2] pry(main)> alice = Ckb::Wallet.from_hex(Ckb::Api.new, "76e853efa8245389e33f6fe49dcbd359eb56be2f6c3594e12521d2a806d32156")
[3] pry(main)> coin_info = admin.created_coin_info("Coin 1")
=> #<Ckb::CoinInfo:0x0000561fee8cf550 @name="Coin 1", @pubkey="024a501efd328e062c8675f2365970728c859c592beeefd6be8ead3d901330bc01">
[4] pry(main)> # coin info represents the meta data for a coin
[5] pry(main)> # we can assemble a wallet for user defined coin with coin info structure
[6] pry(main)> admin_coin1 = admin.udt_wallet(coin_info)
[7] pry(main)> alice_coin1 = alice.udt_wallet(coin_info)
```

Now we can create this coin from a user with CKB capacities(since the cell used to hold the coins will take some capacity):

```bash
[9] pry(main)> admin.get_balance
=> 3737655
[10] pry(main)> # here we are creating 10000000 coins for "Coin 1", we put those coins in a cell with 10000 CKB capacity
[11] pry(main)> admin.create_udt_coin(10000, "Coin 1", 10000000)
[12] pry(main)> admin_coin1.get_balance
=> 10000000
[13] pry(main)> alice_coin1.get_balance
=> 0
```

Transferring coins will be slightly more complicated here: when user 1 transfers some coins to user 2, it usually involves splitting using a cell of user 1 with some coins as input, and 2 new cells as output: cell A transfering some coins to user 2, and cell B transferring the changes back to user 1. There's a question now: who will pay for cell capacity for cell A?

In this Ruby SDK, we implement this using a 3-step solution:

* User 1 creates an output template for cell A
* User 2 signs signatures with his/her own inputs providing capacities for cell A, to ensure security, user 2 can leverage SIGHASH to say that only when the final transaction has cell A, will it be able to unlock user 2's provide inputs.
* User 1 combines inputs and signatures from user 2 with inputs of his/her own to create the final transaction. The final transaction will leverage capacity created from user 2 to store tokens transferred from user 1.

Notice CKB is flexible to implement many other types of transaction for this problem, here we are simply listing one solution here. You are not limited to only this solution.

The following code fulfills this step:

```bash
[15] pry(main)> output = admin_coin1.generate_output(alice_coin1.address, 1234, 3000)
[16] pry(main)> # notice signing inputs require CKB capacity, so we are using
[16] pry(main)> # alice's original wallet, not the coin wallet
[17] pry(main)> signed_data = alice.sign_capacity_for_udt_cell(3000, output)
[18] pry(main)> admin_coin1.send_amount(1234, signed_data[:inputs], signed_data[:outputs])
[19] pry(main)> admin_coin1.get_balance
=> 9998766
[20] pry(main)> alice_coin1.get_balance
=> 1234
```
