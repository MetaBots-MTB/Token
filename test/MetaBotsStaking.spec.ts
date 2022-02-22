import chai, { expect } from 'chai'
import { constants } from 'ethers'
import { network, waffle } from 'hardhat'

import { expandTo18Decimals, mineBlock } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

import { MetaBots, MetaBotsStaking }  from '../typechain';
import { now } from 'lodash'

chai.use(waffle.solidity)

describe('AstroBirdzStaking', () => {
  const { provider, createFixtureLoader } = waffle;
  const [ owner, marketing, team, buyback, user1, user2 ] = provider.getWallets()
  const loadFixture = createFixtureLoader([owner, marketing, team, buyback], provider)

  const configuredLocks = [
    { time: 30 * 86400, apy: 600 }, // 30 days
    { time: 365 * 86400, apy: 1500 }, // 365 days
  ]
  const yearMS = 365 * 24 * 60 * 60

  let metaBots: MetaBots
  let staking: MetaBotsStaking
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)
    metaBots = fixture.metaBots
    staking = fixture.staking

    metaBots.transfer(user1.address, expandTo18Decimals(10000000))
    metaBots.transfer(user2.address, expandTo18Decimals(10000000))
  })

  it('Deployed correctly', async () => {
    expect(await staking.rewardsToken()).to.eq(metaBots.address)
    expect(await staking.stakingToken()).to.eq(metaBots.address)
  })

  describe('Staking', () => {
    const stakeAmount = expandTo18Decimals(5000000)
    const bigStakeAmount = expandTo18Decimals(10000000)

    let startTime: number;
    beforeEach(async function() {
      startTime = (await staking.startTime()).toNumber()
    })

    it('Fails when not started', async () => {
      await expect(staking.connect(user1).stake(stakeAmount, 0)).to.be.revertedWith("Staking not started")
    })

    it('Fails when not lock not exists', async () => {
      await mineBlock(startTime)
      await expect(staking.connect(user1).stake(stakeAmount, configuredLocks.length)).to.be.revertedWith("Lock does not exist")
    })

    it('Fails when not no rewards added', async () => {
      await metaBots.connect(user1).approve(staking.address, stakeAmount)
      await network.provider.send("evm_setNextBlockTimestamp", [startTime])
      await staking.connect(user1).stake(stakeAmount, 0)
      expect(await metaBots.balanceOf(staking.address)).to.eq(stakeAmount)

      await network.provider.send("evm_setNextBlockTimestamp", [startTime + configuredLocks[0].time])
      await expect(staking.connect(user1).exit(0)).to.be.revertedWith("ERC20: transfer amount exceeds balance")
    })

    it('Succeeds for stake 0 when rewards added', async () => {
      const rewardsAmount = expandTo18Decimals(100000000)
      metaBots.transfer(staking.address, rewardsAmount)

      const lock = configuredLocks[0]
      const totalRewards = stakeAmount.mul(lock.apy).mul(lock.time).div(yearMS).div(10000)
      let currentBalance = (await metaBots.balanceOf(user1.address)).sub(stakeAmount)

      await metaBots.connect(user1).approve(staking.address, stakeAmount)
      await network.provider.send("evm_setNextBlockTimestamp", [startTime])
      await staking.connect(user1).stake(stakeAmount, 0)
      expect(await metaBots.balanceOf(staking.address)).to.eq(rewardsAmount.add(stakeAmount))

      await mineBlock(startTime + (lock.time / 4))
      expect(await staking.earned(user1.address, 0)).to.eq(totalRewards.div(4))

      await network.provider.send("evm_setNextBlockTimestamp", [startTime + (lock.time / 2)])
      await staking.connect(user1).getReward(0)
      currentBalance = currentBalance.add(totalRewards.div(2))
      expect(await metaBots.balanceOf(user1.address)).to.eq(currentBalance)

      await network.provider.send("evm_setNextBlockTimestamp", [startTime + lock.time - 1])
      await expect(staking.connect(user1).withdraw(stakeAmount, 0)).to.be.revertedWith("Stake not unlocked")

      await network.provider.send("evm_setNextBlockTimestamp", [startTime + lock.time])
      currentBalance = currentBalance.add(stakeAmount.div(2))
      await (await staking.connect(user1).withdraw(stakeAmount.div(2), 0)).wait()
      expect(await metaBots.balanceOf(user1.address)).to.eq(currentBalance)

      await network.provider.send("evm_setNextBlockTimestamp", [startTime + lock.time + (48 * 60 * 60)])
      currentBalance = currentBalance.add(stakeAmount.div(2)).add(totalRewards.div(2))
      await (await staking.connect(user1).exit(0)).wait()
      expect(await metaBots.balanceOf(user1.address)).to.eq(currentBalance)
    })
  })
})
