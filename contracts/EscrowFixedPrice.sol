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
    event Drained(address indexed token, uint256 collectedFees);
    event Withdraw(address indexed mech, address indexed token, uint256 amount);

    // Wrapped native token address
    address public immutable wrappedNativeToken;
    // Buy back burner address
    address public immutable buyBackBurner;

    // Map of account => map of (token => current balance)
    mapping(address => mapping(address => uint256)) public mapAccountBalances;
    // Map of mech => its current balance
    mapping(address => mapping(address => uint256)) public mapMechBalances;
    // Map of token => collected fees
    mapping(address => uint256) public mapCollectedFees;

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
    function checkAndRecordDeliveryRate(address mech, bytes memory paymentData) external virtual override payable {
        uint256 maxDeliveryRate = IMech(mech).maxDeliveryRate();

        // Get payment token
        address token;
        if (paymentData.length > 0) {
            if (paymentData.length == 32) {
                token = abi.decode(paymentData, (address));
            } else {
                revert();
            }
        }

        // Get account balance
        uint256 balance = mapAccountBalances[msg.sender][token];

        // Check the request delivery rate for a fixed price
        if (balance < maxDeliveryRate) {
            revert InsufficientBalance(balance, maxDeliveryRate);
        }

        // Adjust account balance
        balance -= maxDeliveryRate;
        mapAccountBalances[msg.sender][token] = balance;
    }

    // TODO buyBackBurner does not account for other tokens but WETH, OLAS
    /// @dev Drains collected fees by sending them to a Buy back burner contract.
    function drain(address token) external virtual override {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        uint256 localCollectedFees = mapCollectedFees[token];

        // Check for zero value
        if (localCollectedFees == 0) {
            revert ZeroValue();
        }

        mapCollectedFees[token] = 0;

        // Check token address
        if (token == address (0)) {
            // Wrap native tokens
            _wrap(localCollectedFees);
            // Transfer to Buy back burner
            IToken(wrappedNativeToken).transfer(buyBackBurner, localCollectedFees);
        } else {
            IToken(token).transfer(buyBackBurner, localCollectedFees);
        }

        emit Drained(token, localCollectedFees);

        _locked = 1;
    }

    function _withdraw(address token, uint256 balance) internal {
        bool success;
        // Transfer mech balance
        if (token == address(0)) {
            // solhint-disable-next-line avoid-low-level-calls
            (success, ) = msg.sender.call{value: balance}("");
        } else {
            IToken(token).transfer(msg.sender, balance);
        }

        // Check transfer
        if (!success) {
            revert TransferFailed(token, address(this), msg.sender, balance);
        }
    }

    /// @dev Withdraws funds for a specific mech.
    function withdrawMech(address token) external virtual override {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get mech balance
        uint256 balance = mapMechBalances[msg.sender][token];
        // TODO limits?
        if (balance == 0) {
            revert UnauthorizedAccount(msg.sender);
        }

        _withdraw(token, balance);

        emit Withdraw(msg.sender, token, balance);

        _locked = 1;
    }

    /// @dev Withdraws funds for a specific account.
    function withdrawAccount(address token) external virtual override {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get account balance
        uint256 balance = mapAccountBalances[msg.sender][token];
        // TODO limits?
        if (balance == 0) {
            revert UnauthorizedAccount(msg.sender);
        }

        _withdraw(token, balance);

        emit Withdraw(msg.sender, token, balance);

        _locked = 1;
    }
}