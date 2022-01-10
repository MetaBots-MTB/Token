// npx hardhat run scripts/deploy.ts --network bsctestnet

require("dotenv").config({path: `${__dirname}/.env`})
import { run, ethers, upgrades } from "hardhat"

import { MetaBots, MetaBotsDividendTracker }  from '../typechain'

import MetaBotsAbi from '../artifacts/contracts/MetaBots.sol/MetaBots.json'
import MetaBotsDividendTrackerAbi from '../artifacts/contracts/MetaBotsDividendTracker.sol/MetaBotsDividendTracker.json'

const main = async() => {

  // const signer = ethers.provider.getSigner("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") // hardhat
  // const signer = ethers.provider.getSigner("0xCCD0C72BAA17f4d3217e6133739de63ff6F0b462") // ganache
  const signer = ethers.provider.getSigner("0x5E973EAb14b4Dd9a7690feDd4F9dFfBcf6A4C658") // bsc main and test

  // const psi = "0x6C31B672AB6B4D455608b33A11311cd1C9BdBA1C" // bsc test
  const psi = "0x6e70194F3A2D1D0a917C2575B7e33cF710718a17" // bsc main

  const marketing = "0x90B468248F0C2FD526192dAf1870934360D012E0"
  const dev = "0xe13974E8B27527A4d054C11d6EeA100182cDBF3E"
  const buyback = "0x887DAC98d0A3009a1d245F7F2500aD2eBF19DAeB" // bsc

  // const router: string = ""; // ganache
  // const router: string = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1" // factory test pcs
  const router: string = "0x10ED43C718714eb63d5aA57B78B54704E256024E" // factory main pcs
  
  console.log("deploying")
  
  const metaBots = new ethers.Contract("0x09861d8c3C1350699f8522253E5485f751D6fA78", MetaBotsAbi.abi, signer) as MetaBots
  // const MetaBots = await ethers.getContractFactory("MetaBots")
  // // const metaBots = await upgrades.deployProxy(MetaBots, [
  // //   "MetaBots",
  // //   "MTB",
  // //   marketing,
  // //   dev,
  // //   psi,
  // //   buyback
  // // ], {initializer: 'initialize'}) as MetaBots
  // const metaBots = await upgrades.upgradeProxy("0x09861d8c3C1350699f8522253E5485f751D6fA78", MetaBots) as MetaBots
  // await metaBots.deployed()
  console.log("MetaBots deployed to:", metaBots.address)

  // const dividendTracker = new ethers.Contract("0xE2Cf21f2B980141E685DD158fd5Ef0181393E230", MetaBotsDividendTrackerAbi.abi, signer) as MetaBotsDividendTracker // test
  const dividendTracker = new ethers.Contract("0xA26A367D25dCD20661c8767B5933B7832A0f9909", MetaBotsDividendTrackerAbi.abi, signer) as MetaBotsDividendTracker // main
  // const MetaBotsDividendTracker = await ethers.getContractFactory("MetaBotsDividendTracker")
  // const dividendTracker = await MetaBotsDividendTracker.connect(signer).deploy(psi, metaBots.address) as MetaBotsDividendTracker
  // await dividendTracker.deployed()
  console.log("MetaBotsDividendTracker deployed to:", dividendTracker.address)

  // await (await metaBots.initPSIDividendTracker(dividendTracker.address, router)).wait()
  // await (await metaBots.updatePSIDividendTracker(dividendTracker.address)).wait()
  // console.log("MetaBotsDividendTracker initialized")

  const implAddress = await upgrades.erc1967.getImplementationAddress(metaBots.address)
  console.log("MetaBots implementation address:", implAddress)
  await run("verify:verify", { address: implAddress, constructorArguments: [] })
  console.log("MetaBots implementation verified")
  await run("verify:verify", { address: dividendTracker.address, constructorArguments: [psi, metaBots.address] })
  console.log("MetaBotsDividendTracker verified")
}

main()
//   .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
