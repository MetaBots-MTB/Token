// npx hardhat run scripts/upgrades/upgrade-token.ts --network bscmainnet

require("dotenv").config({path: `${__dirname}/.env`})
import { run, ethers, upgrades, defender } from "hardhat"

import { MetaBots }  from '../../typechain'
import MetaBotsAbi from '../../artifacts/contracts/MetaBots.sol/MetaBots.json'

const main = async() => {

  // const signer = ethers.provider.getSigner("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") // hardhat
  // const signer = ethers.provider.getSigner("0xCCD0C72BAA17f4d3217e6133739de63ff6F0b462") // ganache
  const signer = ethers.provider.getSigner("0x958aB62084bc58C247F435fBdDBf5447C59B4f86") // bsc main and test
  console.log("upgrading")
  
  const metaBots = new ethers.Contract("0x09861d8c3C1350699f8522253E5485f751D6fA78", MetaBotsAbi.abi, signer) as MetaBots
  // const MetaBots = await ethers.getContractFactory("MetaBots")
  // console.log("Preparing MetaBots proposal...");
  // const proposal = await defender.proposeUpgrade(metaBots.address, MetaBots);
  // console.log("MetaBots Upgrade proposal created at:", proposal.url);

  const implAddress = await upgrades.erc1967.getImplementationAddress(metaBots.address)
  console.log("MetaBots implementation address:", implAddress)
  await run("verify:verify", { address: implAddress, constructorArguments: [] })
  console.log("MetaBots implementation verified")
}

main()
//   .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
