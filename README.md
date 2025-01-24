![](https://img.shields.io/badge/Solidity-informational?style=flat&logo=solidity&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Foundry-informational?style=flat&logo=foundry&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Blockchain-informational?style=flat&logo=blockchain&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Smart_Contracts-informational?style=flat&logo=smartcontracts&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/api3-informational?style=flat&logo=api3&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/scroll_L2-informational?style=flat&logo=scroll&logoColor=white&color=6aa6f8)

# ChatterPay

[Chatterpay](chatterpay.net) is a Wallet for WhatsApp that integrates AI and Account Abstraction, enabling any user to use blockchain easily and securely without technical knowledge.

> Built for: [Level Up Hackathon - Ethereum Argentina 2024](https://ethereumargentina.org/) 

> Build By: [mpefaur](https://github.com/mpefaur), [tomasfrancizco](https://github.com/tomasfrancizco), [TomasDmArg](https://github.com/TomasDmArg), [gonzageraci](https://github.com/gonzageraci), [dappsar](https://github.com/dappsar)

__Components__:

- Landing Page ([product](https://chatterpay.net), [source code](https://github.com/P4-Games/ChatterPay))
- User Dashboard Website ([product](https://chatterpay.net/dashboard), [source code](https://github.com/P4-Games/ChatterPay))
- Backend API ([source code](https://github.com/P4-Games/ChatterPay-Backend)) 
- Smart Contracts ([source code](https://github.com/P4-Games/ChatterPay-SmartContracts)) (this Repo)
- Data Indexing (Subgraph) ([source code](https://github.com/P4-Games/ChatterPay-Subgraph))
-   Bot AI Admin Dashboard Website ([product](https://app.chatizalo.com/))
- Bot AI (Chatizalo) ([product](https://chatizalo.com/))
- Bot AI Admin Dashboard Website ([product](https://app.chatizalo.com/))

# About this repo

This repository contains the source code of the Smart Contracts.

__Built With__:

- Framework: [Foundry](https://github.com/foundry-rs/foundry)
- Language: [Solidity](https://solidity-es.readthedocs.io/)
- Smart Contracts Library: [OpenZeppelin](https://www.openzeppelin.com/)
- L2 Blockchain: [Arbitrum](https://github.com/OffchainLabs/arbitrum)
- Account Abstraction: [ERC-4337](https://www.alchemy.com/learn/account-abstraction)
- Web3 Data Feed: [Chainlink](https://github.com/smartcontractkit/chainlink)

# Getting Started

__1. Install Requirements__:

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

```bash
yarn
git submodule update --init --recursive
```

__5. Usage__:

_Build_
```bash
# Local development (faster builds)
yarn run build:local

# Production build (optimized)
yarn run build:prod
```

_Test_
```bash
# Run tests with local profile
yarn run test:local

# Run tests with production profile
yarn run test:prod

# Run coverage tests
yarn run test:coverage

# Run gas report
yarn run test:gas
```

_Format_
```bash
forge fmt
```

_Deploy_
```bash
# Deploy Simulation
yarn run deploy:simulate

# Real Deploy
yarn run deploy:prod

# Real Deploy + Verify contracts
yarn run deploy:verify

# Deploy only ChatterPay contract
yarn run deploy:chatterpay

# Deploy + Verify only ChatterPay contract
yarn run deploy:chatterpay:verify
```

# Additional Info

## Technical Documentation

If you would like to explore more details about the source code, you can review this [link](.doc/content.md).

## Contribution

Thank you for considering helping out with the source code! We welcome contributions from anyone on the internet, and are grateful for even the smallest of fixes!

If you'd like to contribute to ChatterPay, please fork, fix, commit and send a pull request for the maintainers to review and merge into the main code base.

Please make sure your contributions adhere to our [coding guidelines](./.doc/development/coding-guidelines.md).

_Contributors_: 

* [tomasDmArg](https://github.com/TomasDmArg) - [tomasfrancizco](https://github.com/tomasfrancizco) - [dappsar](https://github.com/dappsar)
* See more in: <https://github.com/P4-Games/chatterPay-SmartContracts/graphs/contributors>