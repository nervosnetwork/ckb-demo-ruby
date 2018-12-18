# How to use

## Prerequisites

First you will need to have [ckb](https://github.com/nervosnetwork/ckb) compiled of course. Feel free to just following the official build steps in the README. We will customize configs later.

You will also need [mruby-contracts](https://github.com/nervosnetwork/mruby-contracts). Follow the steps in the README to build it, you will need the generated mruby contract file at `build/argv_source_entry`.

If you don't want to build mruby-contracts yourself, we have a prebuilt binary at [here](https://github.com/nervosnetwork/binary/raw/master/contracts/mruby/argv_source_entry).

## Configure CKB

Before we are using this SDK, we will need a customized CKB config for the following purposes:

* We will need a stable RPC port we can connect to.
* We will need to include mruby contract as a system cell. Notice it's also possible to create a new cell with mruby contract as the cell data, then referencing this cell later. Here for simplicity, we are sticking to a system cell.
* Depending on computing resource you have, you can also set CKB to dummy mining mode to save CPU resources. In dummy mode, CKB will randomly sleep for certain amount of time acting as a "mining" time instead of doing expensive calculations.

First you need a dummy folder to store all the configs, assuming we are using `/home/ubuntu/node1`, we can do:

```bash
$ cp -r <path to ckb>/nodes_template /home/ubuntu/node1
$ cp <path to mruby-contracts>/build/argv_source_entry /home/ubuntu/node1/spec/cells/
```

In this newly created folder, change the file `default.json` to the following content:

```
{
    "data_dir": "default",
    "ckb": {
        "chain": "spec/dev.json"
    },
    "logger": {
        "file": "ckb.log",
        "filter": "info,chain=debug",
        "color": true
    },
    "rpc": {
        "listen_addr": "0.0.0.0:8114"
    },
    "network": {
        "listen_addresses": ["/ip4/0.0.0.0/tcp/8115"],
        "boot_nodes": [],
        "reserved_nodes": [],
        "max_peers": 8
    },
    "sync": {
        "verification_level": "Full",
        "orphan_block_limit": 1024
    },
    "pool": {
        "max_pool_size": 10000,
        "max_orphan_size": 10000,
        "max_proposal_size": 10000,
        "max_cache_size": 1000,
        "max_pending_size": 10000
    },
    "miner": {
        "new_transactions_threshold": 8,
        "type_hash": "0xcf7294651a9e2033243b04cfd3fa35097d56b811824691a75cd29d50ac23720a",
        "rpc_url": "http://127.0.0.1:8114/",
        "poll_interval": 5,
        "max_transactions": 10000,
        "max_proposals": 10000
    }
}
```

Notice the miner type hash here is the wallet address for the private key `e79f3207ea4980b7fed79956d5934249ceac4751a4fae01a0f7c4a96884bc4e3`.

Also, change the file `spec/dev.json` to the following content:

```
{
    "name": "ckb",
    "genesis": {
        "seal": {
            "nonce": 0,
            "proof": [0]
        },
        "version": 0,
        "parent_hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "timestamp": 0,
        "txs_commit": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "txs_proposal": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "difficulty": "0x100",
        "cellbase_id": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "uncles_hash": "0x0000000000000000000000000000000000000000000000000000000000000000"
    },
    "params": {
        "initial_block_reward": 50000
    },
    "system_cells": [
        {"path": "cells/verify"},
        {"path": "cells/always_success"},
        {"path": "cells/argv_source_entry"}
    ],
    "pow": {
        "Dummy": null
    }
}
```

And you can try launching CKB node and miner using configs here:

```bash
./target/release/ckb -c /home/ubuntu/node1/default.json run
./target/release/ckb -c /home/ubuntu/node1/default.json miner
```

Here release version of ckb is used, though debug version will also work.

You can verify CKB is running by issuing RPC calls:

```bash
$ curl -d '{"id": 2, "jsonrpc": "2.0", "method":"get_tip_header","params": []}' -H 'content-type:application/json' 'http://localhost:8114'
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

Please be noted that the SDK depends on the [bitcoin-secp256k1](https://github.com/cryptape/ruby-bitcoin-secp256k1) gem, which requires manual install of secp256k1 library. Follow the [prerequiste](https://github.com/cryptape/ruby-bitcoin-secp256k1#prerequiste) part in the gem to install secp256k1 library locally.

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

If your miner balance is always 0, you might want to run the following command:

```bash
[8] pry(main)> miner.address
=> "0xcf7294651a9e2033243b04cfd3fa35097d56b811824691a75cd29d50ac23720a"
```

And see if the miner address returned in your environment matches the value here, if not, it means that the mruby contract cell compiled in your environment is not exactly the same as the one we use here. In this case, please edit `type_hash` part in `/home/ubuntu/foo/bar/spec.json` with your value, and restart CKB, now miner should be able to pick up tokens mined in newer blocks.

### User defined token

We can also create user defined token that's separate from CKB. A new user defined token is made of 2 parts:

* A token name
* Token's admin pubkey, only token's admin can issue new tokens. Other user can only transfer already created tokens to others.

Ruby SDK here provides an easy way to create a token from an existing wallet

```bash
[1] pry(main)> admin = Ckb::Wallet.from_hex(Ckb::Api.new, "e79f3207ea4980b7fed79956d5934249ceac4751a4fae01a0f7c4a96884bc4e3")
[2] pry(main)> alice = Ckb::Wallet.from_hex(Ckb::Api.new, "76e853efa8245389e33f6fe49dcbd359eb56be2f6c3594e12521d2a806d32156")
[3] pry(main)> token_info = admin.created_token_info("Token 1")
=> #<Ckb::TokenInfo:0x0000561fee8cf550 @name="Token 1", @pubkey="024a501efd328e062c8675f2365970728c859c592beeefd6be8ead3d901330bc01">
[4] pry(main)> # token info represents the meta data for a token
[5] pry(main)> # we can assemble a wallet for user defined token with token info structure
[6] pry(main)> admin_token1 = admin.udt_wallet(token_info)
[7] pry(main)> alice_token1 = alice.udt_wallet(token_info)
```

Now we can create this token from a user with CKB capacities(since the cell used to hold the tokens will take some capacity):

```bash
[9] pry(main)> admin.get_balance
=> 3737655
[10] pry(main)> # here we are creating 10000000 tokens for "Token 1", we put those tokens in a cell with 10000 CKB capacity
[11] pry(main)> admin.create_udt_token(10000, "Token 1", 10000000)
[12] pry(main)> admin_token1.get_balance
=> 10000000
[13] pry(main)> alice_token1.get_balance
=> 0
```

Now that the token is created, we can implement a token transfer process between CKB capacities and user defined tokens. Specifically, we are demostrating the following process:

* Alice signs signatures providing a certain number of CKB capacities in exchange of some user defined tokens. Notice CKB contracts here can ensure that no one can spend alice's signed capacities without providing tokens for Alice
* Then admin provides user defined tokens for Alice in exchange for Alice's capacities.

Notice CKB is flexible to implement many other types of transaction for this problem, here we are simply listing one solution here. You are not limited to only this solution.

The following code fulfills this step:

```bash
[15] pry(main)> # Alice is paying 10999 CKB capacities for 12345 token 1, alice will also spare 3000 CKB capacities to hold the returned token 1.
[15] pry(main)> partial_tx = alice_token1.generate_partial_tx_for_udt_cell(12345, 3000, 10999)
[18] pry(main)> admin_token1.send_amount(12345, partial_tx)
[19] pry(main)> admin_token1.get_balance
=> 9987655
[20] pry(main)> alice_token1.get_balance
=> 12345
```

### User Defined Token which uses only one cell per wallet:

```bash
[1] pry(main)> admin = Ckb::Wallet.from_hex(Ckb::Api.new, "e79f3207ea4980b7fed79956d5934249ceac4751a4fae01a0f7c4a96884bc4e3")
[2] pry(main)> alice = Ckb::Wallet.from_hex(Ckb::Api.new, "76e853efa8245389e33f6fe49dcbd359eb56be2f6c3594e12521d2a806d32156")
[3] pry(main)> token_info2 = admin.created_token_info("Token 2")
[4] pry(main)> admin_cell_token2 = admin.udt_account_wallet(token_info2)
[5] pry(main)> alice_cell_token2 = alice.udt_account_wallet(token_info2)
[6] pry(main)> admin.create_udt_token(10000, "Token 2", 10000000, account_wallet: true)
[7] pry(main)> alice.create_udt_account_wallet_cell(3000, token_info2)
[8] pry(main)> admin_cell_token2.send_tokens(12345, alice_cell_token2)
[9] pry(main)> admin_cell_token2.get_balance
[10] pry(main)> alice_cell_token2.get_balance
```

NOTE: While it might be possible to mix the 2 ways of using user defined token above in one token, we don't really recommend that since it could be the source of a lot of confusions.
