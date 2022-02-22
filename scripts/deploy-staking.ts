// npx hardhat run scripts/deploy-staking.ts --network bsctestnet

require("dotenv").config({path: `${__dirname}/.env`})
import { run, ethers, upgrades } from "hardhat"

import { MetaBots, MetaBotsStaking }  from '../typechain'

import MetaBotsAbi from '../artifacts/contracts/MetaBots.sol/MetaBots.json'
import MetaBotsStakingAbi from '../artifacts/contracts/MetaBotsStaking.sol/MetaBotsStaking.json'
import { now } from "lodash"

const main = async() => {

  // const signer = ethers.provider.getSigner("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") // hardhat
  // const signer = ethers.provider.getSigner("0xCCD0C72BAA17f4d3217e6133739de63ff6F0b462") // ganache
  const signer = ethers.provider.getSigner("0x5E973EAb14b4Dd9a7690feDd4F9dFfBcf6A4C658") // bsc main and test
  
  console.log("deploying")
  
  const metaBots = new ethers.Contract("0x09861d8c3C1350699f8522253E5485f751D6fA78", MetaBotsAbi.abi, signer) as MetaBots // bsc main and test

  // staking
  // let staking = new ethers.Contract("0x433FF4d2aB2a37130eA0DCC54F827E1BfdD54be4", MetaBotsStakingAbi.abi, signer) as MetaBotsStaking; // bsc test
  const MetaBotsStaking = await ethers.getContractFactory("MetaBotsStaking");
  // staking = await upgrades.upgradeProxy(staking.address, MetaBotsStaking) as MetaBotsStaking
  const staking = await upgrades.deployProxy(MetaBotsStaking, [
    metaBots.address,
    metaBots.address,
    now()
  ], {initializer: 'initialize'}) as MetaBotsStaking;
  await (await metaBots.excludeFromFeesAndDividends(staking.address)).wait()
  console.log("MetaBotsStaking deployed:", staking.address);

  const stakingImplAddress = await upgrades.erc1967.getImplementationAddress(staking.address)
  console.log("MetaBotsStaking implementation address:", stakingImplAddress);
  await run("verify:verify", { address: stakingImplAddress, constructorArguments: [] });
  console.log("MetaBotsStaking implementation verified");
}

main()
//   .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
