![](https://img.shields.io/badge/Solidity-informational?style=flat&logo=solidity&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Foundry-informational?style=flat&logo=foundry&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Blockchain-informational?style=flat&logo=blockchain&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/Smart_Contracts-informational?style=flat&logo=smartcontracts&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/api3-informational?style=flat&logo=api3&logoColor=white&color=6aa6f8)
![](https://img.shields.io/badge/scroll_L2-informational?style=flat&logo=scroll&logoColor=white&color=6aa6f8)

# ChatterPay

[Chatterpay](https://chatterpay.net) is a Wallet for WhatsApp that integrates AI and Account Abstraction, enabling any user to use blockchain easily and securely without technical knowledge.

> Create Wallet, Transfer, Swap, and mint NFTs — directly from WhatsApp!

> Built for: [Level Up Hackathon - Ethereum Argentina 2024](https://ethereumargentina.org/) & [Ethereum Uruguay 2024](https://www.ethereumuruguay.org/)

> Build By: [mpefaur](https://github.com/mpefaur), [tomasfrancizco](https://github.com/tomasfrancizco), [TomasDmArg](https://github.com/TomasDmArg), [gonzageraci](https://github.com/gonzageraci), [dappsar](https://github.com/dappsar)


**Get started with our Bot 🤖**:

[![WhatsApp Bot](https://img.shields.io/badge/Start%20on%20WhatsApp-25D366.svg?style=flat&logo=whatsapp&logoColor=white)](https://wa.me/5491164629653)


**Components**:

- Landing Page ([product](https://chatterpay.net), [source code](https://github.com/P4-Games/ChatterPay))
- User Dashboard Website ([product](https://chatterpay.net/dashboard), [source code](https://github.com/P4-Games/ChatterPay))
- Backend API ([source code](https://github.com/P4-Games/ChatterPay-Backend)) 
- Smart Contracts ([source code](https://github.com/P4-Games/ChatterPay-SmartContracts)) (this Repo)
- Data Indexing (Subgraph) ([source code](https://github.com/P4-Games/ChatterPay-Subgraph))
- Bot AI (Chatizalo) ([product](https://chatizalo.com/))
- Bot AI Admin Dashboard Website ([product](https://app.chatizalo.com/))

<p>&nbsp;</p>

![Components Interaction](https://github.com/P4-Games/ChatterPay-Backend/blob/develop/.doc/technical-overview/chatterpay-architecture-conceptual-view.jpg?raw=true)

# About this repo

This repository contains the source code of the Smart Contracts.

**Built With**:

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
yarn run test:coverage:local

# Run gas report
yarn run test:gas
```

_Format_
```bash
forge fmt
```

_Deploy_
```bash

# Real Deploy
yarn run deploy:arbitrum-sepolia

# Real Deploy + Verify contracts
yarn run deploy:arbitrum-sepolia:verify

# Deploy only ChatterPay contract
yarn run deploy:chatterpay

# Deploy + Verify only ChatterPay contract
yarn run deploy:chatterpay:verify
```

# Additional Info

**Technical Documentation**:

If you would like to explore more details about the source code, you can review this [link](.doc/content.md).

**Contribution**:

Thank you for considering helping out with the source code! We welcome contributions from anyone on the internet, and are grateful for even the smallest of fixes!

If you'd like to contribute to ChatterPay, please fork, fix, commit and send a pull request for the maintainers to review and merge into the main code base. If you wish to submit more complex changes though, please check up with the [core devs](https://github.com/P4-Games/chatterPay-SmartContracts/graphs/contributors) first to ensure those changes are in line with the general philosophy of the project and/or get some early feedback which can make both your efforts much lighter as well as our review and merge procedures quick and simple.

Please make sure your contributions adhere to our [coding guidelines](./.doc/development/coding-guidelines.md).

_Contributors_: 

* Core Developers: [tomasDmArg](https://github.com/TomasDmArg) - [tomasfrancizco](https://github.com/tomasfrancizco) - [dappsar](https://github.com/dappsar)

* Auditors: [EperezOk](https://github.com/EperezOk) - [0xJuancito](https://github.com/0xJuancito) - [Magehernan](https://github.com/Magehernan)

* See more in: <https://github.com/P4-Games/chatterPay-SmartContracts/graphs/contributors>

<p>&nbsp;</p>

---

[![X](https://img.shields.io/badge/X-%231DA1F2.svg?style=flat&logo=twitter&logoColor=white)](https://x.com/chatterpay)
[![Instagram](https://img.shields.io/badge/Instagram-%23E4405F.svg?style=flat&logo=instagram&logoColor=white)](https://www.instagram.com/chatterpayofficial)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-%230077B5.svg?style=flat&logo=linkedin&logoColor=white)](https://www.linkedin.com/company/chatterpay)
[![Facebook](https://img.shields.io/badge/Facebook-%231877F2.svg?style=flat&logo=facebook&logoColor=white)](https://www.facebook.com/chatterpay)
[![YouTube](https://img.shields.io/badge/YouTube-%23FF0000.svg?style=flat&logo=youtube&logoColor=white)](https://www.youtube.com/@chatterpay)
[![WhatsApp Community](https://img.shields.io/badge/WhatsApp%20Community-25D366.svg?style=flat&logo=whatsapp&logoColor=white)](https://chat.whatsapp.com/HZJrBEUYyoF8FtchfJhzmZ)
