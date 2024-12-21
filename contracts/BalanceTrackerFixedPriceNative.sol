// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BalanceTrackerFixedPriceBase, ZeroAddress, InsufficientBalance, TransferFailed} from "./BalanceTrackerFixedPriceBase.sol";
import {IMech} from "./interfaces/IMech.sol";

interface IToken {
    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWrappedToken {
    function deposit() external payable;
}

contract BalanceTrackerFixedPriceNative is BalanceTrackerFixedPriceBase {
    // Wrapped native token address
    address public immutable wrappedNativeToken;

    /// @dev BalanceTrackerFixedPrice constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _buyBackBurner Buy back burner address.
    /// @param _wrappedNativeToken Wrapped native token address.
    constructor(address _mechMarketplace, address _buyBackBurner, address _wrappedNativeToken)
        BalanceTrackerFixedPriceBase(_mechMarketplace, _buyBackBurner)
    {
        // Check for zero address
        if (_wrappedNativeToken == address(0)) {
            revert ZeroAddress();
        }

        wrappedNativeToken = _wrappedNativeToken;
    }

    function _checkNativeValue() internal virtual override {}

    function _getRequiredFunds(address, uint256 balanceDiff) internal virtual override returns (uint256) {
        if (msg.value < balanceDiff) {
            revert InsufficientBalance(msg.value, balanceDiff);
        }
        return msg.value;
    }

    function _wrap(uint256 amount) internal virtual {
        IWrappedToken(wrappedNativeToken).deposit{value: amount}();
    }

    function _drain(uint256 amount) internal virtual override {
        // Wrap native tokens
        _wrap(amount);
        // Transfer to Buy back burner
        IToken(wrappedNativeToken).transfer(buyBackBurner, amount);

        emit Drained(wrappedNativeToken, amount);
    }

    function _withdraw(uint256 balance) internal virtual override {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = msg.sender.call{value: balance}("");

        // Check transfer
        if (!success) {
            revert TransferFailed(address(0), address(this), msg.sender, balance);
        }

        emit Withdraw(msg.sender, address(0), balance);
    }

    // Deposits funds for requester.
    receive() external payable {
        // Update account balances
        mapRequesterBalances[msg.sender] += msg.value;

        emit Deposit(msg.sender, address(0), msg.value);
    }
}