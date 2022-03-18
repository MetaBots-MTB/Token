// SPDX-License-Identifier: MIT

/**
 *
 *    _____          __        __________        __          
 *   /     \   _____/  |______ \______   \ _____/  |_  ______
 *  /  \ /  \_/ __ \   __\__  \ |    |  _//  _ \   __\/  ___/
 * /    Y    \  ___/|  |  / __ \|    |   (  <_> )  |  \___ \ 
 * \____|__  /\___  >__| (____  /______  /\____/|__| /____  >
 *         \/     \/          \/       \/                 \/ 
 *
 * MetaBots token contract
 * 
 * Starting fees subtracted on trades:
 * 2% metabots buyback
 * 2% development
 * 2% marketing
 * 2% auto liquidity
 * 2% PSI dividend
 *
 */

pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import './token/ERC1363/ERC1363Upgradeable.sol';
import './token/ERC2612/ERC2612Upgradeable.sol';
import './token/extensions/ERC20BurnableUpgradeable.sol';
import './token/extensions/ERC20TokenRecoverUpgradeable.sol';
import './interfaces/IDEXFactory.sol';
import './interfaces/IDEXPair.sol';
import './interfaces/IDEXRouter.sol';
import './interfaces/IDividendTracker.sol';

contract MetaBots is 
    OwnableUpgradeable, 
    ERC20Upgradeable,
    ERC1363Upgradeable, 
    ERC2612Upgradeable, 
    ERC20BurnableUpgradeable, 
    ERC20TokenRecoverUpgradeable {

    IDividendTracker public dividendTracker;
    uint256 public gasForProcessing;

    // store addresses that are automatic market maker (dex) pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;
    
    mapping(address => bool) public feeExcludedAddresses;

    address payable public buybackAddress;
    uint256 public buybackFee;
    address payable public developmentAddress;
    uint256 public developmentFee;
    address payable public marketingAddress;
    uint256 public marketingFee;
    address public liquidityAddress;
    uint256 public liquidityFee;
    address public psiTokenAddress;
    uint256 public psiFee;

    struct LastSell {
        uint256 time;
        uint256 amount;
    }
    mapping(address => LastSell) public lastSells;
    uint256 public sellLimit; // sell limit in percentage of tokens in liquidity if sellAmountLimited is true
    bool public sellAmountLimited; // by default false
    bool public tradingPaused; // by default false
    
    IDEXRouter public dexRouter;
    address public dexPair;
    
    bool private inSwapAndLiquify;
    bool public swapAndLiquifyEnabled;
    uint256 public minTokensBeforeSwap;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event SendDividends(uint256 tokensSwapped, uint256 amount);
    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );
    event UpdateDefaultDexRouter(
        address indexed newAddress,
        address indexed oldAddress,
        address newPair,
        address oldPair
    );
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    
    modifier lockTheSwap {
        inSwapAndLiquify = true;
         _;
        inSwapAndLiquify = false;
    }

    receive() external payable {}

    function initialize(
        string memory _name,
        string memory _symbol,
        address payable marketingAddress_,
        address payable developmentAddress_,
        address psiAddress_,
        address payable buybackAddress_
    ) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ERC20_init_unchained(_name, _symbol);
        __EIP712_init_unchained(_name, "1");
        __ERC2612_init_unchained();

        uint256 supply = 10 ** (9 + decimals()); // 1 billion supply
        swapAndLiquifyEnabled = true;
        buybackFee = 200;
        developmentFee = 200;
        marketingFee = 200;
        liquidityFee = 200;
        psiFee = 200;
        sellLimit = 500; // 5% of tokens in liquidity
        
        buybackAddress = buybackAddress_;
        developmentAddress = developmentAddress_;
        marketingAddress = marketingAddress_;
        liquidityAddress = _msgSender();
        psiTokenAddress = psiAddress_;

        // use by default 300,000 gas to process auto-claiming dividends
        gasForProcessing = 300000;
        minTokensBeforeSwap = 100000 * (10 ** decimals()); // min 10k tokens in contract before swapping

        tradingPaused = true;
        sellAmountLimited = true;

        _mint(_msgSender(), supply);
    }

    function initPSIDividendTracker(IDividendTracker _dividendTracker, address router_) external onlyOwner {
        require(address(dividendTracker) == address(0), "ALREADY_INITIALIZED");
        dividendTracker = _dividendTracker;
        dividendTracker.excludeFromDividends(address(dividendTracker));
        
         // Create a dex pair for this new token
         dexRouter = IDEXRouter(router_);
        dexPair = IDEXFactory(dexRouter.factory()).createPair(address(this), dexRouter.WETH());
        _setAutomatedMarketMakerPair(dexPair, true);

        dividendTracker.excludeFromDividends(address(dexRouter));
        dividendTracker.excludeFromDividends(address(0x000000000000000000000000000000000000dEaD));

        excludeFromFeesAndDividends(address(this));
        excludeFromFeesAndDividends(_msgSender());
    }

    function updatePSIDividendTracker(IDividendTracker _dividendTracker) external onlyOwner {
        dividendTracker = _dividendTracker;
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(dexPair);
        dividendTracker.excludeFromDividends(address(dexRouter));
        dividendTracker.excludeFromDividends(address(0x000000000000000000000000000000000000dEaD));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(_msgSender());
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual 
        override(ERC1363Upgradeable, ERC2612Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setFees(
        uint256 _buybackFee,
        uint256 _developmentFee,
        uint256 _marketingFee,
        uint256 _liquidityFee,
        uint256 _psiFee
    ) public onlyOwner {
        require(
            (_buybackFee + _developmentFee + _marketingFee + _liquidityFee + _psiFee) <= 2000,
            'FEE_HIGHER_THAN_20%'
        );
        buybackFee = _buybackFee;
        developmentFee = _developmentFee;
        marketingFee = _marketingFee;
        liquidityFee = _liquidityFee;
        psiFee = _psiFee;
    }
    
    function setBuybackAddress(address payable buybackAddress_) public onlyOwner {
        require(buybackAddress_ != address(0), 'ZERO_ADDRESS');
        buybackAddress = buybackAddress_;
    }
    
    function changeMarketingAddress(address payable marketingAddress_) public onlyOwner {
        require(marketingAddress_ != address(0), 'ZERO_ADDRESS');
        marketingAddress = marketingAddress_;
    }

    function changeDevelopmentAddress(address payable developmentAddress_) public onlyOwner {
        require(developmentAddress_ != address(0), 'ZERO_ADDRESS');
        developmentAddress = developmentAddress_;
    }

    function changePSIAddress(address PSIAddress_) public onlyOwner {
        require(PSIAddress_ != address(0), 'ZERO_ADDRESS');
        psiTokenAddress = PSIAddress_;
    }

    function changeLiquidityAddress(address payable liquidityAddress_) public onlyOwner {
        require(liquidityAddress_ != address(0), 'ZERO_ADDRESS');
        liquidityAddress = liquidityAddress_;
    }
    
    function setFeeExcludedForAddress(address excludedA, bool value) public onlyOwner {
        feeExcludedAddresses[excludedA] = value;
    }
    function excludeFromFeesAndDividends(address excludedA) public onlyOwner {
        setFeeExcludedForAddress(excludedA, true);
        dividendTracker.excludeFromDividends(excludedA);
    }

    function changeMinTokensBeforeSwap(uint256 minTokensBeforeSwap_) public onlyOwner {
        minTokensBeforeSwap = minTokensBeforeSwap_;
    }

    function addNewRouter(address _router, bool makeDefault) external onlyOwner {
        dividendTracker.excludeFromDividends(_router);

        IDEXRouter _dexRouter = IDEXRouter(_router);
        address _dexPair = IDEXFactory(_dexRouter.factory()).getPair(address(this), _dexRouter.WETH());
        if (_dexPair == address(0))
            _dexPair = IDEXFactory(_dexRouter.factory()).createPair(address(this), _dexRouter.WETH());
        _setAutomatedMarketMakerPair(_dexPair, true);

        if (makeDefault) {
            emit UpdateDefaultDexRouter(_router, address(dexRouter), _dexPair, dexPair);
            dexRouter = _dexRouter;
            dexPair = _dexPair;
        }
    }
    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(value || pair != dexPair, 'CANNOT_REMOVE_DEFAULT_PAIR');
        _setAutomatedMarketMakerPair(pair, value);
    }
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, 'VALUE_ALREADY_SET');

        automatedMarketMakerPairs[pair] = value;
        if (value && address(dividendTracker) != address(0)) dividendTracker.excludeFromDividends(pair);
        emit SetAutomatedMarketMakerPair(pair, value);
    }
    function updateGasForProcessing(uint256 newValue) external onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, 'VALUE_NOT_BETWEEN_200000_500000');
        gasForProcessing = newValue;
    }

    function processDividendTracker(uint256 gas) external {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        swapAndLiquifyEnabled = _enabled;
    }
    
    function changeSellLimit(uint256 _sellLimit) public onlyOwner {
        require(_sellLimit >= 100 && _sellLimit <= 10000, "VALUE_NOT_BETWEEN_100_10000");
        sellLimit = _sellLimit;
    }
    function toggleSellAmountLimited() external onlyOwner() {
        sellAmountLimited = !sellAmountLimited;
    }
    function toggleTradingPaused() external onlyOwner {
        require(address(dividendTracker) != address(0), "DIV_TRACKER_NOT_INITIALIZED");
        tradingPaused = !tradingPaused;
    }

    function multiTransfer(address[] memory receivers, uint256[] memory amounts) external {
        require(receivers.length != 0, 'NO_RECEIVERS');
        require(receivers.length == amounts.length, 'ARRAY_LENGTH_NOT_EQUAL');
        for (uint256 i = 0; i < receivers.length; i++) {
            transfer(receivers[i], amounts[i]);
        }
    }
    
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        require(balanceOf(sender) >= amount, "ERC20: transfer amount exceeds balance");
        if(((automatedMarketMakerPairs[recipient] && balanceOf(recipient) != 0) ||
            automatedMarketMakerPairs[sender]) && 
            sender != liquidityAddress && recipient != liquidityAddress) {
            require(!tradingPaused, "TRADING_PAUSED");
        }
        checkSellLimit(sender, recipient, amount);

        if( feeExcludedAddresses[recipient] ||
            feeExcludedAddresses[sender] || 
            (!automatedMarketMakerPairs[recipient] && !automatedMarketMakerPairs[sender])) {
            _transferExcluded(sender, recipient, amount);
        } else {
            _transferWithFees(sender, recipient, amount);    
        }
    }
    function checkSellLimit(address sender, address recipient, uint256 amount) private {
        // return if not sell, or is liquidity address
        if (!sellAmountLimited || 
            !automatedMarketMakerPairs[recipient] || 
            sender == liquidityAddress || 
            sender == address(this)) {
            return;
        }

        uint256 _limit = (sellLimit * IERC20Upgradeable(address(this)).balanceOf(recipient)) / 10000;
        if (lastSells[sender].time > (block.timestamp - 1 days)) {
            _limit = lastSells[sender].amount >= _limit ? 0 : _limit - lastSells[sender].amount;
            lastSells[sender].time = block.timestamp + 
                ((block.timestamp - lastSells[sender].time) * lastSells[sender].amount) / 
                (lastSells[sender].amount + amount);
            lastSells[sender].amount += amount;
        } else {
            lastSells[sender] = LastSell(block.timestamp, amount);
        }
        require(amount <= _limit, 'SELL_LIMIT_REACHED');
    }

    function _transferExcluded(address sender, address recipient, uint256 amount) private {
        _fixDividendTrackerBalancer(sender, recipient, amount);
        super._transfer(sender, recipient, amount);
    }
    function _transferWithFees(address sender, address recipient, uint256 amount) private {
        uint256 fees = ((amount * liquidityFee) / 10**4) +
            ((amount * buybackFee) / 10**4) +
            ((amount * marketingFee) / 10**4) +
            ((amount * psiFee) / 10**4) +
            ((amount * developmentFee) / 10**4);
        amount -= fees;
        super._transfer(sender, address(this), fees);

        _fixDividendTrackerBalancer(sender, recipient, amount);
        
        // swap fees before transfer has happened and after dividend balances are done
        uint256 contractTokenBalance = balanceOf(address(this));
        if (
            contractTokenBalance >= minTokensBeforeSwap &&
            !inSwapAndLiquify &&
            !automatedMarketMakerPairs[sender] &&
            swapAndLiquifyEnabled
        ) {
            swapAndLiquify(contractTokenBalance);
        }
        
        super._transfer(sender, recipient, amount);

        if (address(dividendTracker) != address(0) && !inSwapAndLiquify) {
            try dividendTracker.process(gasForProcessing) returns (
                uint256 iterations,
                uint256 claims,
                uint256 lastProcessedIndex
            ) {
                emit ProcessedDividendTracker(
                    iterations,
                    claims,
                    lastProcessedIndex,
                    true,
                    gasForProcessing,
                    tx.origin
                );
            } catch {}
        }
    }

    function _fixDividendTrackerBalancer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        if (address(dividendTracker) != address(0)) {
            if (sender == recipient) {
                try dividendTracker.setBalance(payable(sender), balanceOf(sender)) {} catch {}
            } else {
                try dividendTracker.setBalance(payable(sender), balanceOf(sender) - amount) {} catch {}
                try dividendTracker.setBalance(payable(recipient), balanceOf(recipient) + amount) {} catch {}
            }
        }
    }
    
    function performSwapAndLiquify() external onlyOwner {
        uint256 contractTokenBalance = balanceOf(address(this));
        if (contractTokenBalance >= minTokensBeforeSwap && !inSwapAndLiquify && swapAndLiquifyEnabled) {
            swapAndLiquify(contractTokenBalance);
        }
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        uint256 totalFees = liquidityFee + marketingFee + developmentFee + buybackFee + psiFee ;
        uint256 forLiquidity = (contractTokenBalance * liquidityFee) / totalFees;

        uint256 initialBalance = address(this).balance;
        swapTokensForEth(contractTokenBalance - (forLiquidity / 2)); // withold half of the liquidity tokens
        uint256 swappedBalance = address(this).balance - initialBalance;
        uint256 feeBalance = swappedBalance - 
            ((swappedBalance * (liquidityFee / 2)) / (totalFees - (liquidityFee / 2)));
        totalFees -= liquidityFee;

        marketingAddress.transfer((feeBalance * marketingFee) / totalFees);
        developmentAddress.transfer((feeBalance * developmentFee) / totalFees);
        
        swapAndSendDividends((feeBalance * psiFee) / totalFees);

        addLiquidity(forLiquidity / 2, (swappedBalance - feeBalance));
        
        buybackAddress.transfer(address(this).balance - initialBalance); // buybackfee + leftovers

        emit SwapAndLiquify(contractTokenBalance, swappedBalance, forLiquidity / 2);
    }
     
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the dex pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        _approve(address(this), address(dexRouter), tokenAmount);

        // make the swap
        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(dexRouter), tokenAmount);

        // add the liquidity
        dexRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityAddress,
            block.timestamp
        );
    }

    function swapAndSendDividends(uint256 ethAmount) private {
        uint256 psiBalanceBefore = IERC20(psiTokenAddress).balanceOf(address(dividendTracker));
        swapETHForPSI(ethAmount, address(dividendTracker));
        uint256 dividends = IERC20(psiTokenAddress).balanceOf(address(dividendTracker)) - psiBalanceBefore;

        dividendTracker.distributeDividends(dividends);
        emit SendDividends(ethAmount, dividends);
    }

    function swapETHForPSI(uint256 ethAmount, address recipient) private {
        // generate the uniswap pair path of weth -> PSI
        address[] memory path = new address[](2);
        path[0] = dexRouter.WETH();
        path[1] = psiTokenAddress;

        // make the swap
        dexRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0, // accept any amount of PSI
            path,
            recipient,
            block.timestamp
        );
    }
}