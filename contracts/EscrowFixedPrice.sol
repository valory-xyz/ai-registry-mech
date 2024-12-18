// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EscrowBase} from "./EscrowBase.sol";
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

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Not enough balance to cover costs.
/// @param current Current balance.
/// @param required Required balance.
error InsufficientBalance(uint256 current, uint256 required);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Account is unauthorized.
/// @param account Account address.
error UnauthorizedAccount(address account);

/// @dev Failure of a transfer.
/// @param token Address of a token.
/// @param from Address `from`.
/// @param to Address `to`.
/// @param amount Amount value.
error TransferFailed(address token, address from, address to, uint256 amount);

contract EscrowFixedPrice is EscrowBase {
    // Wrapped native token address
    address public immutable wrappedNativeToken;
    // Buy back burner address
    address public immutable buyBackBurner;

    /// @param _wrappedNativeToken Wrapped native token address.
    /// @param _buyBackBurner Buy back burner address.
    constructor(address _mechMarketplace, address _wrappedNativeToken, address _buyBackBurner)
        EscrowBase(_mechMarketplace)
    {
        // Check for zero address
        if (_wrappedNativeToken == address(0) || _buyBackBurner == address(0)) {
            revert ZeroAddress();
        }

        wrappedNativeToken = _wrappedNativeToken;
        buyBackBurner = _buyBackBurner;
    }

    function _wrap(uint256 amount) internal virtual {
        IWrappedToken(wrappedNativeToken).deposit{value: amount}();
    }

    // Check and escrow delivery rate
    function checkAndEscrowDeliveryRate(address mech) external virtual override payable {
        uint256 maxDeliveryRate = IMech(mech).maxDeliveryRate();

        // Check the request delivery rate for a fixed price
        if (msg.value < maxDeliveryRate) {
            revert InsufficientBalance(msg.value, maxDeliveryRate);
        }
    }

    /// @dev Withdraws funds for a specific mech.
    function withdraw() external virtual override {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get mech balance
        uint256 balance = mapMechBalances[msg.sender];
        if (balance == 0) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Transfer mech balance
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = msg.sender.call{value: balance}("");
        if (!success) {
            revert TransferFailed(address(0), address(this), msg.sender, balance);
        }

        emit Withdraw(msg.sender, balance);

        _locked = 1;
    }

    /// @dev Drains collected fees by sending them to a Buy back burner contract.
    function drain() external virtual override {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        uint256 localCollectedFees = collectedFees;

        // Check for zero value
        if (localCollectedFees == 0) {
            revert ZeroValue();
        }

        collectedFees = 0;

        // Wrap native tokens
        _wrap(localCollectedFees);

        // Transfer to Buy back burner
        IToken(wrappedNativeToken).transfer(buyBackBurner, localCollectedFees);

        emit Drained(localCollectedFees);

        _locked = 1;
    }
}