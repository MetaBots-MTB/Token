# MetaBots contracts

This project is using [Hardhat](https://hardhat.org/getting-started/) for development, compiling, testing and deploying. The development tool used for development is [Visual Studio Code](https://code.visualstudio.com/) which has [great plugins](https://hardhat.org/guides/vscode-tests.html) for solidity development and mocha testing.

## Contracts

* Binance Chain
  * MetaBots : [](https://bscscan.com/address/)
  * MetaBotsDividendTracker : [](https://bscscan.com/address/)

* Binance Test Chain
  * MetaBots : [0x09861d8c3c1350699f8522253e5485f751d6fa78](https://testnet.bscscan.com/address/0x09861d8c3c1350699f8522253e5485f751d6fa78)
  * MetaBotsDividendTracker : [0xE2Cf21f2B980141E685DD158fd5Ef0181393E230](https://testnet.bscscan.com/address/0xE2Cf21f2B980141E685DD158fd5Ef0181393E230)

### Basic Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, a sample script that deploys that contract, and an example of a task implementation, which simply lists the available accounts.

Try running some of the following tasks:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
node scripts/sample-script.js
npx hardhat help
```

### Scripts

Use the scripts in the "scripts" folder. Each script has the command to start it on top.

Make sure you have set the right settings in your ['.env' file](https://www.npmjs.com/package/dotenv). You have to create this file with the following contents yourself:

```node
BSC_PRIVATE_KEY=<private_key>
BSC_TEST_PRIVATE_KEY=<private_key>

BSC_API_TOKEN=<bscscan_api_token>
```