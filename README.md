![](https://img.shields.io/badge/Solidity-informational?style=flat&logo=solidity&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Foundry-informational?style=flat&logo=foundry&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Blockchain-informational?style=flat&logo=blockchain&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Smart_Contracts-informational?style=flat&logo=smartcontracts&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/api3-informational?style=flat&logo=api3&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/scroll_L2-informational?style=flat&logo=scroll&logoColor=white&color=6aa6f8)

# ChatterPay

Chatterpay is a Wallet for WhatsApp that integrates AI and Account Abstraction, enabling any user to use blockchain easily and securely without technical knowledge.

> Built for: [Level Up Hackathon - Ethereum Argentina 2024](https://ethereumargentina.org/) 

> Build By: [mpefaur](https://github.com/mpefaur), [tomasfrancizco](https://github.com/tomasfrancizco), [TomasDmArg](https://github.com/TomasDmArg), [gonzageraci](https://github.com/gonzageraci),  [dappsar](https://github.com/dappsar)


__Components__:

- Landing Page ([product](https://chatterpay.net), [source code](https://github.com/P4-Games/ChatterPay))
- User Dashboard Website ([product](https://chatterpay.net/dashboard), [source code](https://github.com/P4-Games/ChatterPay))
- Backend API ([source code](https://github.com/P4-Games/ChatterPay-Backend)) 
- Smart Contracts ([source code](https://github.com/P4-Games/ChatterPay-SmartContracts)) (this Repo)
- Data Indexing (Subgraph) ([source code](https://github.com/P4-Games/ChatterPay-Subgraph))
- Bot AI (Chatizalo) ([product](https://chatizalo.com/))
- Bot AI Admin Dashboard Website ([product](https://app.chatizalo.com/))


# About this repo

This repository contains the source code of the Smart Contracts.

__Build With__:

- Framework: [Foundry](https://github.com/foundry-rs/foundry)
- Language: [Solidity](https://solidity-es.readthedocs.io/)
- Smart Contracts Library: [OpenZeppelin](https://www.openzeppelin.com/)
- L2 Blockchain: [Scroll](https://github.com/scroll-tech)
- Account Abstraction L2 Keystore: [Scroll L1SLOAD](https://dev.to/turupawn/l1sload-el-nuevo-opcode-para-keystores-seguras-y-escalables-50of)
- Web3 Data Feed: [api3](https://api3.org/)

If you would like to explore the details of the contracts in-depth, you can review them at this [link](.doc/technical-overview/overview.md).



# Getting Started

__1. Install these Requirements__:

- [git](https://git-scm.com/)
- [foundry](https://book.getfoundry.sh/getting-started/installation)


__2. Clone repository__:

```bash
   git clone https://github.com/P4-Games/ChatterPay-SmartContracts
   cd ChatterPay-SmartContracts
```

__3. Complete .env file__: 

Create a .env file in the root folder and populate it with the following keys and values:


```sh
ETH_SEPOLIA_RPC_URL=Your node provider URL for Sepolia
SCROLL_SEPOLIA_RPC_URL=Your node provider URL for Scroll-Sepolia
PRIVATE_KEY=Your private key
SCROLLSCAN_API_KEY=Your Scrollscan API key
BACKEND_EOA=chatterpay backend EOA wallet address
BACKEND_PK=chatterpay bachend private key
```

__4. Install Dependencies__:

```sh
yarn
```

```sh
git submodule update --init --recursive
```

__5. Usage__:

_Build_

```shell
$ forge clean && forge build
```

_Test_

```shell
$ forge test
```

_Format_

```shell
$ forge fmt
```

_Gas Snapshots_

```shell
$ forge snapshot
```

_Anvil_

```shell
$ anvil
```

_Deploy_

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

_Cast_

```shell
$ cast <subcommand>
```

_Help_

```shell
$ forge --help
$ anvil --help
$ cast --help
```

_Static Checks_

Solidity Static Analysis with [Slither](https://github.com/crytic/slither).  
To install slither go to [this link](https://github.com/crytic/slither#how-to-install).

```shell
$ slither .
```

