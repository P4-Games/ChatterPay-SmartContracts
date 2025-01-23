![](https://img.shields.io/badge/Solidity-informational?style=flat&logo=solidity&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Foundry-informational?style=flat&logo=foundry&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Blockchain-informational?style=flat&logo=blockchain&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Smart_Contracts-informational?style=flat&logo=smartcontracts&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/api3-informational?style=flat&logo=api3&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/scroll_L2-informational?style=flat&logo=scroll&logoColor=white&color=6aa6f8)

# ChatterPay

[Chatterpay](chatterpay.net) is a Wallet for WhatsApp that integrates AI and Account Abstraction, enabling any user to use blockchain easily and securely without technical knowledge.

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

Create a .env file in the root folder and populate it with the keys indicated in file [example_env](./example_env)


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
forge clean && forge build
```

_Test_

```shell
yarn run test:modules
```

_Format_

```shell
forge fmt
```

_Gas Snapshots_

```shell
forge snapshot
```

_Anvil_

```shell
anvil
```

_Cast_

```shell
cast <subcommand>
```

_Deploy_

```shell
forge clean & forge build

# Deploy Simulation
forge script script/DeployAllContracts.s.sol \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Real Deploy
forge script script/DeployAllContracts.s.sol \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast

# Real Deploy + Verify contracts in Etherscal
forge script script/DeployAllContracts.s.sol \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

_Help_

```shell
forge --help
anvil --help
cast --help
```

_Static Checks_

Solidity Static Analysis with [Slither](https://github.com/crytic/slither).  
To install slither go to [this link](https://github.com/crytic/slither#how-to-install).

```shell
slither .
```

# Additional Info

## Technical Documentation

If you would like to explore more details about the source code, you can review this [link](.doc/content.md).


## Contribution

Thank you for considering helping out with the source code! We welcome contributions from anyone on the internet, and are grateful for even the smallest of fixes!

If you'd like to contribute to ChatterPay, please fork, fix, commit and send a pull request for the maintainers to review and merge into the main code base. If you wish to submit more complex changes though, please check up with the [core devs](https://github.com/P4-Games/chatterPay-SmartContracts/graphs/contributors) first to ensure those changes are in line with the general philosophy of the project and/or get some early feedback which can make both your efforts much lighter as well as our review and merge procedures quick and simple.

Please make sure your contributions adhere to our [coding guidelines](./.doc/development/coding-guidelines.md).

_Contributors_: 

* [tomasfrancizco](https://github.com/tomasfrancizco) - [dappsar](https://github.com/dappsar) - [tomasDmArg](https://github.com/TomasDmArg) - 

* See more in: <https://github.com/P4-Games/chatterPay-SmartContracts/graphs/contributors>

