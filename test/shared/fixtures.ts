import { Wallet, Contract, providers, utils, constants } from 'ethers'
import { waffle, ethers, upgrades } from 'hardhat'

import { expandTo18Decimals } from './utilities'

import { MetaBots, MetaBotsDividendTracker, MetaBotsStaking, WBNB, FakePSI, PancakeFactory, PancakeRouter, IPancakePair }  from '../../typechain';

import MetaBotsAbi from '../../artifacts/contracts/MetaBots.sol/MetaBots.json'
import MetaBotsDividendTrackerAbi from '../../artifacts/contracts/MetaBotsDividendTracker.sol/MetaBotsDividendTracker.json'
import MetaBotsStakingAbi from '../../artifacts/contracts/MetaBotsStaking.sol/MetaBotsStaking.json'
import WBNBAbi from '../../artifacts/contracts/test/WBNB.sol/WBNB.json'
import FakePSIAbi from '../../artifacts/contracts/test/FakePSI.sol/FakePSI.json'
import PancakeFactoryAbi from '../../artifacts/contracts/test/PancakeFactory.sol/PancakeFactory.json'
import PancakeRouterAbi from '../../artifacts/contracts/test/PancakeRouter.sol/PancakeRouter.json'
import IPancakePairAbi from '../../artifacts/contracts/test/PancakeRouter.sol/IPancakePair.json'
import { now } from 'lodash';

const overrides = {
  gasLimit: 9500000
}

interface V2Fixture {
  WBNB: WBNB 
  PSI: FakePSI
  factory: PancakeFactory
  router: PancakeRouter
  metaBots: MetaBots
  dividendTracker: MetaBotsDividendTracker
  pair: IPancakePair
  staking: MetaBotsStaking
}

export async function v2Fixture([wallet, marketing, team, buyback]: Wallet[], provider: providers.Web3Provider): Promise<V2Fixture> {
  // base tokens
  const WBNB = await waffle.deployContract(wallet, WBNBAbi, [], overrides) as unknown as WBNB
  const PSI = await waffle.deployContract(wallet, FakePSIAbi, [], overrides) as unknown as FakePSI

  // pancake router
  const factory = await waffle.deployContract(wallet, PancakeFactoryAbi, [wallet.address], overrides) as unknown as PancakeFactory
  const router = await waffle.deployContract(wallet, PancakeRouterAbi, [factory.address, WBNB.address], overrides) as unknown as PancakeRouter

  await PSI.approve(router.address, constants.MaxUint256);
  await router.addLiquidityETH(PSI.address, expandTo18Decimals(40000), 0, 0, wallet.address, constants.MaxUint256, { value: expandTo18Decimals(20) })

  // metaBots
  const MetaBots = await ethers.getContractFactory("MetaBots");
  const metaBots = await upgrades.deployProxy(MetaBots, [
    "MetaBots",
    "MTB",
    marketing.address,
    team.address,
    PSI.address,
    buyback.address
  ], {initializer: 'initialize'}) as MetaBots;
  const dividendTracker = await waffle.deployContract(wallet, MetaBotsDividendTrackerAbi, [PSI.address, metaBots.address], overrides) as unknown as MetaBotsDividendTracker
  await metaBots.initPSIDividendTracker(dividendTracker.address, router.address)

  // pair
  const pairAddress = await factory.getPair(metaBots.address, WBNB.address)
  const pair = new Contract(pairAddress, IPancakePairAbi.abi, provider) as IPancakePair;

  // staking
  const MetaBotsStaking = await ethers.getContractFactory("MetaBotsStaking");
  const staking = await upgrades.deployProxy(MetaBotsStaking, [
    metaBots.address,
    metaBots.address,
    now() + 100000,
  ], {initializer: 'initialize'}) as MetaBotsStaking;
  await (await metaBots.excludeFromFeesAndDividends(staking.address)).wait()

  return {
    WBNB,
    PSI,
    factory,
    router,
    metaBots,
    dividendTracker,
    pair,
    staking,
  }
}
