// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BalanceTrackerBase, ZeroAddress, InsufficientBalance, TransferFailed} from "../../BalanceTrackerBase.sol";
import {IMech} from "../../interfaces/IMech.sol";

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

contract BalanceTrackerFixedPriceNative is BalanceTrackerBase {
    // Wrapped native token address
    address public immutable wrappedNativeToken;

    /// @dev BalanceTrackerFixedPrice constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _buyBackBurner Buy back burner address.
    /// @param _wrappedNativeToken Wrapped native token address.
    constructor(address _mechMarketplace, address _buyBackBurner, address _wrappedNativeToken)
        BalanceTrackerBase(_mechMarketplace, _buyBackBurner)
    {
        // Check for zero address
        if (_wrappedNativeToken == address(0)) {
            revert ZeroAddress();
        }

        wrappedNativeToken = _wrappedNativeToken;
    }

    /// @dev Drains specified amount.
    /// @param amount Token amount.
    function _drain(uint256 amount) internal virtual override {
        // Wrap native tokens
        _wrap(amount);
        // Transfer to Buy back burner
        IToken(wrappedNativeToken).transfer(buyBackBurner, amount);

        emit Drained(wrappedNativeToken, amount);
    }

    /// @dev Gets native token value or restricts receiving one.
    /// @return Received value.
    function _getOrRestrictNativeValue() internal virtual override returns (uint256) {
        // Update balance with native value
        if (msg.value > 0) {
            emit Deposit(msg.sender, address(0), msg.value);
        }

        return msg.value;
    }

    /// @dev Gets required token funds.
    /// @return Received amount.
    function _getRequiredFunds(address, uint256) internal virtual override returns (uint256) {
        return 0;
    }

    /// @dev Withdraws funds.
    /// @param account Account address.
    /// @param amount Token amount.
    function _withdraw(address account, uint256 amount) internal virtual override {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = account.call{value: amount}("");

        // Check transfer
        if (!success) {
            revert TransferFailed(address(0), address(this), account, amount);
        }

        emit Withdraw(msg.sender, address(0), amount);
    }

    /// @dev Wraps native token.
    /// @notice Pay attention and override, if necessary.
    /// @param amount Token amount.
    function _wrap(uint256 amount) internal virtual {
        IWrappedToken(wrappedNativeToken).deposit{value: amount}();
    }

    /// @dev Deposits funds for requester.
    receive() external payable {
        // Update account balances
        mapRequesterBalances[msg.sender] += msg.value;

        emit Deposit(msg.sender, address(0), msg.value);
    }
}