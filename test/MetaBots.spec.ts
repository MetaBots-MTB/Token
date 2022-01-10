import chai, { expect } from 'chai'
import { constants } from 'ethers'
import { waffle } from 'hardhat'

import { expandTo18Decimals } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

import { MetaBots, MetaBotsDividendTracker, WBNB, FakePSI, PancakeFactory, PancakeRouter, IPancakePair }  from '../typechain';

chai.use(waffle.solidity)

describe('MetaBots', () => {
  const { provider, createFixtureLoader } = waffle;
  const [ owner, marketing, team, buyback, user1, user2 ] = provider.getWallets()
  const loadFixture = createFixtureLoader([owner, marketing, team, buyback], provider)

  let buyPath: string[] = []
  let sellPath: string[] = []

  let WBNB: WBNB
  let PSI: FakePSI
  let factory: PancakeFactory
  let router: PancakeRouter
  let metaBots: MetaBots
  let dividendTracker: MetaBotsDividendTracker
  let pair: IPancakePair
  beforeEach(async function() {

    const fixture = await loadFixture(v2Fixture)
    WBNB = fixture.WBNB
    PSI = fixture.PSI
    factory = fixture.factory
    router = fixture.router
    metaBots = fixture.metaBots
    dividendTracker = fixture.dividendTracker
    pair = fixture.pair

    buyPath = [ WBNB.address, metaBots.address ]
    sellPath = [ metaBots.address, WBNB.address ]
  })

  const ethLiquidity = expandTo18Decimals(10)
  const tokenLiquidity = expandTo18Decimals(200000000)
  const addTokenLiquidity = async() => {
    await metaBots.approve(router.address, constants.MaxUint256);
    await router.addLiquidityETH(metaBots.address, tokenLiquidity, tokenLiquidity, ethLiquidity, owner.address, constants.MaxUint256, { value: ethLiquidity });
  }

  it('Deployed correctly', async () => {
    expect(await metaBots.dexRouter()).to.eq(router.address)
    expect(await metaBots.automatedMarketMakerPairs(await metaBots.dexPair())).to.eq(true)
    expect(await metaBots.psiTokenAddress()).to.eq(PSI.address)
    expect(await metaBots.marketingAddress()).to.eq(marketing.address)
    expect(await metaBots.developmentAddress()).to.eq(team.address)
    expect(await metaBots.buybackAddress()).to.eq(buyback.address)
    expect(await metaBots.liquidityAddress()).to.eq(owner.address)
    expect(await metaBots.totalSupply()).to.eq(expandTo18Decimals(1000000000))
  })

  it('Not possible to initializeDividendTracker again', async () => {
    await expect(metaBots.initPSIDividendTracker(dividendTracker.address, router.address)).to.be.revertedWith("ALREADY_INITIALIZED")
  })

  describe('Transfers', () => {
    it('Succeed when enabled with 0 fees applied', async () => {
      await metaBots.transfer(user1.address, expandTo18Decimals(10))
      await metaBots.connect(user1).transfer(user2.address, expandTo18Decimals(10))
    })

    it('Succeed for adding liquidity by owner, fail for trades', async () => {
      await addTokenLiquidity()
      await expect(router.connect(user1).swapETHForExactTokens(expandTo18Decimals(1), buyPath, user1.address, constants.MaxUint256, { value: expandTo18Decimals(1) }))
        .to.be.revertedWith("Pancake: TRANSFER_FAILED: TRADING_PAUSED")
    })
  })

  describe('Fees', () => {
    beforeEach(async() => {
      await addTokenLiquidity();
      await metaBots.toggleTradingPaused();
    })

    it('Not payed by excluded wallet', async () => {
      await metaBots.excludeFromFeesAndDividends(user1.address)
      await router.connect(user1).swapETHForExactTokens(expandTo18Decimals(1), buyPath, user1.address, constants.MaxUint256, { value: expandTo18Decimals(1) })
      expect(await metaBots.balanceOf(user1.address)).to.eq(expandTo18Decimals(1))
      
      await metaBots.connect(user1).approve(router.address, expandTo18Decimals(1))
      await router.connect(user1).swapExactTokensForETH(expandTo18Decimals(1), 0, sellPath, user1.address, constants.MaxUint256)
      expect(await metaBots.balanceOf(user1.address)).to.eq(0)
    })

    it('Fails when exceeding sell limit', async () => {
      const limit = tokenLiquidity.div(20) // 5%
      await metaBots.transfer(user1.address, limit.mul(3))
      await metaBots.connect(user1).approve(router.address, limit.mul(3));
      await expect(router.connect(user1).swapExactTokensForETHSupportingFeeOnTransferTokens(limit.add(1), 0, sellPath, user1.address, constants.MaxUint256))
        .to.be.revertedWith("TransferHelper: TRANSFER_FROM_FAILED: SELL_LIMIT_REACHED")

      await router.connect(user1).swapExactTokensForETHSupportingFeeOnTransferTokens(limit.div(2), 0, sellPath, user1.address, constants.MaxUint256)
      await router.connect(user1).swapExactTokensForETHSupportingFeeOnTransferTokens(limit.div(2), 0, sellPath, user1.address, constants.MaxUint256)
      await expect(router.connect(user1).swapExactTokensForETHSupportingFeeOnTransferTokens(expandTo18Decimals(500000), 0, sellPath, user1.address, constants.MaxUint256))
        .to.be.revertedWith("TransferHelper: TRANSFER_FROM_FAILED: SELL_LIMIT_REACHED")

      await metaBots.toggleSellAmountLimited()
      await router.connect(user1).swapExactTokensForETHSupportingFeeOnTransferTokens(expandTo18Decimals(500000), 0, sellPath, user1.address, constants.MaxUint256)
    })

    it('Correctly applied on buy', async () => {
      const liquidityBalance = await pair.balanceOf(owner.address)

      await router.connect(user1).swapETHForExactTokens(expandTo18Decimals(1000000), buyPath, user1.address, constants.MaxUint256, { value: expandTo18Decimals(2) })

      expect(await metaBots.balanceOf(user1.address)).to.eq(expandTo18Decimals(900000))
      expect(await PSI.balanceOf(dividendTracker.address)).to.eq(0) // fees are not transfered on buys
      expect(await metaBots.balanceOf(marketing.address)).to.eq(0)
      expect((await pair.balanceOf(owner.address)).sub(liquidityBalance)).to.eq(0)

      await metaBots.performSwapAndLiquify() // or sell, this is mainly for testing purposes
      expect(await metaBots.balanceOf(marketing.address)).to.eq(0)
      expect(await PSI.balanceOf(dividendTracker.address)).to.eq('1929521149723327045')
    })

    it('Correctly applied on sell', async () => {
      const liquidityBalance = await pair.balanceOf(owner.address)
      const marketingBalanceBefore = await marketing.getBalance()
      const teamBalanceBefore = await team.getBalance()
      const buybackBalanceBefore = await buyback.getBalance()

      await router.connect(user1).swapETHForExactTokens(expandTo18Decimals(1000000), buyPath, user1.address, constants.MaxUint256, { value: expandTo18Decimals(2) })

      await metaBots.connect(user1).transfer(user2.address, expandTo18Decimals(300000)); // needed because someone needs to retrieve dividend
      await metaBots.connect(user1).approve(router.address, expandTo18Decimals(300000));
      await router.connect(user1).swapExactTokensForETHSupportingFeeOnTransferTokens(expandTo18Decimals(300000), 0, sellPath, user1.address, constants.MaxUint256)

      expect(await metaBots.balanceOf(user1.address)).to.eq(expandTo18Decimals(300000))
      expect(await PSI.balanceOf(dividendTracker.address)).to.eq('2') // all distributed. Leaves 2?
      expect(await PSI.balanceOf(user1.address)).to.eq('1228920217148780719')
      expect(await PSI.balanceOf(user2.address)).to.eq('1228920217148780719')
      expect((await marketing.getBalance()).sub(marketingBalanceBefore)).to.eq('1309064095805805')
      expect((await team.getBalance()).sub(teamBalanceBefore)).to.eq('1309064095805805')
      expect((await buyback.getBalance()).sub(buybackBalanceBefore)).to.eq('1309064095805808') // might be slightly more because of 'leftovers' from adding liquidity
      expect((await pair.balanceOf(owner.address)).sub(liquidityBalance)).to.eq('2914192110374722216')
    })

    it('Works with multiple buys and sells', async () => {
      await router.swapETHForExactTokens(expandTo18Decimals(1), buyPath, user1.address, constants.MaxUint256, { value: expandTo18Decimals(5) })

      const wallets = provider.getWallets().slice(5, 12)
      for(let idx = 0; idx < wallets.length; idx++) {
        const wallet = wallets[idx]
        await router.connect(wallet).swapETHForExactTokens(expandTo18Decimals(1000000), buyPath, wallet.address, constants.MaxUint256, { value: expandTo18Decimals(5) })
        expect(await metaBots.balanceOf(wallet.address)).to.eq(expandTo18Decimals(900000))
        expect(await dividendTracker.balanceOf(wallet.address)).to.eq(expandTo18Decimals(900000))

        if (idx == 3 || idx == 5) {
          await metaBots.connect(wallets[idx-1]).approve(router.address, expandTo18Decimals(900000));
          await router.connect(wallets[idx-1]).swapExactTokensForETHSupportingFeeOnTransferTokens(expandTo18Decimals(900000), 0, sellPath, wallets[idx-1].address, constants.MaxUint256)

          expect(await metaBots.balanceOf(wallets[idx-1].address)).to.eq(expandTo18Decimals(0))
          expect(await dividendTracker.balanceOf(wallets[idx-1].address)).to.eq(expandTo18Decimals(0))
        }
      }
    })
  })
})
