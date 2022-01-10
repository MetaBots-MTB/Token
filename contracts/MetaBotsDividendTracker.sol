// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import './libraries/IterableMapping.sol';
import './token/DividendPayingToken.sol';
import './token/extensions/ERC20TokenRecover.sol';
import './interfaces/IDividendTracker.sol';

contract MetaBotsDividendTracker is Ownable, DividendPayingToken, ERC20TokenRecover, IDividendTracker {
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public override lastProcessedIndex;

    mapping(address => bool) public override excludedFromDividends;

    mapping(address => uint256) public override lastClaimTimes;

    uint256 public override claimWait;
    uint256 public override minimumTokenBalanceForDividends;

    constructor(address _dividendToken, address _parentToken)
        DividendPayingToken('MetaBots Dividend Tracker', 'MTBDT', _dividendToken, _parentToken)
    {
        claimWait = 3600; // every hour on default
        minimumTokenBalanceForDividends = IERC20(parentToken).totalSupply() / 100000; // 0.001%
    }

    //== BEP20 owner function ==
    function getOwner() public view override returns (address) {
        return owner();
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) public override onlyOwnerOrParentToken {
        require(tokenAddress != dividendToken, 'CANNOT_RETRIEVE_DIV_TOKEN');
        super.recoverERC20(tokenAddress, tokenAmount);
    }

    function _transfer(
        address,
        address,
        uint256
    ) internal pure override {
        require(false, 'NO_TRANSFERS_ALLOWED');
    }

    function withdrawDividend() public pure override(DividendPayingToken, IDividendPayingTokenInterface) {
        require(
            false,
            "MetaBotsDividendTracker: Disabled. Use the 'claim' function on the MetaBots token contract."
        );
    }

    function excludeFromDividends(address account) external override onlyOwnerOrParentToken {
        require(!excludedFromDividends[account], 'ACCOUNT_ALREADY_EXCLUDED');
        excludedFromDividends[account] = true;

        _setBalance(account, 0);
        tokenHoldersMap.remove(account);

        emit ExcludeFromDividends(account);
    }

    function includeInDividends(address account) external override onlyOwnerOrParentToken {
        require(excludedFromDividends[account], 'ACCOUNT_NOT_EXCLUDED');

        excludedFromDividends[account] = false;
        _setBalance(account, 0);

        emit IncludedInDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external override onlyOwnerOrParentToken {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, 'VALUE_NOT_BETWEEN_3600_86400');
        require(newClaimWait != claimWait, 'VALUE_ALREADY_SET');
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function updateMinTokenBalance(uint256 minTokens) external override onlyOwnerOrParentToken {
        minimumTokenBalanceForDividends = minTokens;
    }

    function getLastProcessedIndex() external view override returns (uint256) {
        return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view override returns (uint256) {
        return tokenHoldersMap.keys.length;
    }

    function getAccount(address _account)
        public
        view
        override
        returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable
        )
    {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if (index >= 0) {
            if (uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index - int256(lastProcessedIndex);
            } else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex
                    ? tokenHoldersMap.keys.length - lastProcessedIndex
                    : 0;
                iterationsUntilProcessed = index + int256(processesUntilEndOfArray);
            }
        }

        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ? lastClaimTime + claimWait : 0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ? nextClaimTime - block.timestamp : 0;
    }

    function getAccountAtIndex(uint256 index)
        external
        view
        override
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        if (index >= tokenHoldersMap.size()) return (address(0), -1, -1, 0, 0, 0, 0, 0);
        address account = tokenHoldersMap.getKeyAtIndex(index);
        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
        if (lastClaimTime > block.timestamp) {
            return false;
        }

        return (block.timestamp - lastClaimTime) >= claimWait;
    }

    function ensureBalance(bool _process) external override {
        ensureBalanceForUser(payable(_msgSender()), _process);
    }

    function ensureBalanceForUsers(bytes calldata accounts, bool _process)
        external
        override
        onlyOwnerOrParentToken
    {   
        uint addressCount = accounts.length / 20;
        for(uint256 i = 0; i < addressCount; i++){
            ensureBalanceForUser(payable(bytesToAddress(accounts[i*20:(i+1)*20])), _process);
        }
    }
    function bytesToAddress(bytes calldata data) private pure returns (address addr) {
        bytes memory b = data;
        assembly { addr := mload(add(b, 20)) }
    }

    function ensureBalanceForUser(address payable account, bool _process) public override onlyOwnerOrParentToken {
        uint256 balance = IERC20(parentToken).balanceOf(account);

        if (excludedFromDividends[account]) return;

        if (balance != balanceOf(account)) {
            if (balance >= minimumTokenBalanceForDividends) {
                _setBalance(account, balance);
                tokenHoldersMap.set(account, balance);
            } else {
                _setBalance(account, 0);
                tokenHoldersMap.remove(account);
            }
        }

        if (_process) processAccount(account, false);
    }

    function setBalance(address payable account, uint256 newBalance) external override onlyOwnerOrParentToken {
        if (excludedFromDividends[account]) return;

        if (newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
            tokenHoldersMap.set(account, newBalance);
        } else {
            _setBalance(account, 0);
            tokenHoldersMap.remove(account);
        }

        processAccount(account, true);
    }

    function process(uint256 gas)
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

        if (numberOfTokenHolders == 0) {
            return (0, 0, lastProcessedIndex);
        }

        uint256 _lastProcessedIndex = lastProcessedIndex;

        uint256 gasUsed = 0;

        uint256 gasLeft = gasleft();

        uint256 iterations = 0;
        uint256 claims = 0;

        while (gasUsed < gas && iterations < numberOfTokenHolders) {
            _lastProcessedIndex++;

            if (_lastProcessedIndex >= tokenHoldersMap.keys.length) {
                _lastProcessedIndex = 0;
            }

            address account = tokenHoldersMap.keys[_lastProcessedIndex];

            if (canAutoClaim(lastClaimTimes[account])) {
                if (processAccount(payable(account), true)) {
                    claims++;
                }
            }

            iterations++;

            uint256 newGasLeft = gasleft();
            if (gasLeft > newGasLeft) gasUsed = gasUsed + (gasLeft - newGasLeft);
            gasLeft = newGasLeft;
        }

        lastProcessedIndex = _lastProcessedIndex;

        return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic)
        public
        override
        onlyOwnerOrParentToken
        returns (bool)
    {
        uint256 amount = _withdrawDividendOfUser(account);

        if (amount > 0) {
            lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
            return true;
        }

        return false;
    }
}
