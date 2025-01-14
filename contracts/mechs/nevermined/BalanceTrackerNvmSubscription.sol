// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BalanceTrackerBase, ZeroAddress, ZeroValue, InsufficientBalance, ReentrancyGuard} from "../../BalanceTrackerBase.sol";

interface IERC1155 {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @param tokenId Token Id.
    /// @return Amount of tokens owned.
    function balanceOf(address account, uint256 tokenId) external view returns (uint256);

    /// @dev Burns a specified amount of account's tokens.
    /// @param account Account address.
    /// @param tokenId Token Id.
    /// @param amount Amount of tokens.
    function burn(address account, uint256 tokenId, uint256 amount) external;

    /// @dev Transfers tokens.
    /// @param from Source address.
    /// @param to Destination address.
    /// @param id Token Id.
    /// @param amount Token amount.
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external;
}

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev No incoming msg.value is allowed.
/// @param amount Value amount.
error NoDepositAllowed(uint256 amount);

contract BalanceTrackerNvmSubscription is BalanceTrackerBase {
    event WithdrawSubscription(address indexed account, address indexed token, uint256 indexed tokenId, uint256 amount);
    event RequesterCreditsRedeemed(address indexed account, uint256 amount);

    // TODO: setup, taken from subscription?
    uint256 public constant NVM_FEE = 100;

    // Subscription NFT
    address public immutable subscriptionNFT;
    // Subscription token Id
    uint256 public immutable subscriptionTokenId;

    /// @dev BalanceTrackerSubscription constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _buyBackBurner Buy back burner address.
    /// @param _subscriptionNFT Subscription NFT address.
    /// @param _subscriptionTokenId Subscription token Id.
    constructor(address _mechMarketplace, address _buyBackBurner, address _subscriptionNFT, uint256 _subscriptionTokenId)
        BalanceTrackerBase(_mechMarketplace, _buyBackBurner)
    {
        if (_subscriptionNFT == address(0)) {
            revert ZeroAddress();
        }

        if (_subscriptionTokenId == 0) {
            revert ZeroValue();
        }

        subscriptionNFT = _subscriptionNFT;
        subscriptionTokenId = _subscriptionTokenId;
    }

    /// @dev Adjusts initial requester balance accounting for max request delivery rate (credit).
    /// @param balance Initial requester balance.
    /// @param maxDeliveryRate Max delivery rate.
    function _adjustInitialBalance(
        address requester,
        uint256 balance,
        uint256 maxDeliveryRate,
        bytes memory
    ) internal virtual override returns (uint256) {
        // Get requester actual subscription balance
        uint256 subscriptionBalance = IERC1155(subscriptionNFT).balanceOf(requester, subscriptionTokenId);

        // Adjust requester balance with maxDeliveryRate credits
        balance += maxDeliveryRate;

        // Check the request delivery rate for a fixed price
        if (subscriptionBalance < balance) {
            revert InsufficientBalance(subscriptionBalance, balance);
        }

        return balance;
    }

    /// @dev Adjusts final requester balance accounting for possible delivery rate difference (credit).
    /// @param requester Requester address.
    /// @param rateDiff Delivery rate difference.
    /// @return Adjusted balance.
    function _adjustFinalBalance(address requester, uint256 rateDiff) internal virtual override returns (uint256) {
        uint256 balance = mapRequesterBalances[requester];

        // This must never happen as max delivery rate is always bigger or equal to the actual delivery rate
        if (rateDiff > balance) {
            revert Overflow(rateDiff, balance);
        }

        // Adjust requester credit balance
        return (balance - rateDiff);
    }

    // TODO: behavior with buyBackBurner?
    /// @dev Drains specified amount.
    /// @param amount Amount value.
    function _drain(uint256 amount) internal virtual override {}

    /// @dev Gets fee composed of marketplace fee and another one, if applicable.
    function _getFee() internal view virtual override returns (uint256) {
        return NVM_FEE + super._getFee();
    }

    /// @dev Gets native token value or restricts receiving one.
    /// @return Received value.
    function _getOrRestrictNativeValue() internal virtual override returns (uint256) {
        // Check for msg.value
        if (msg.value > 0) {
            revert NoDepositAllowed(msg.value);
        }

        return 0;
    }

    /// @dev Gets required token funds.
    function _getRequiredFunds(address, uint256) internal virtual override returns (uint256) {
        return 0;
    }

    /// @dev Withdraws funds.
    /// @param account Account address.
    /// @param amount Token amount.
    function _withdraw(address account, uint256 amount) internal virtual override {
        // Transfer tokens
        IERC1155(subscriptionNFT).safeTransferFrom(address(this), account, subscriptionTokenId, amount, "");

        emit WithdrawSubscription(msg.sender, subscriptionNFT, subscriptionTokenId, amount);
    }

    /// @dev Redeem requester credits.
    /// @param requester Requester address.
    function redeemRequesterCredits(address requester) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get requester credit balance
        uint256 balance = mapRequesterBalances[requester];
        // Get requester actual subscription balance
        uint256 subscriptionBalance = IERC1155(subscriptionNFT).balanceOf(requester, subscriptionTokenId);

        // This must never happen
        if (subscriptionBalance < balance) {
            balance = subscriptionBalance;
        }

        // Check for zero value
        if (balance == 0) {
            revert ZeroValue();
        }

        // Clear balances
        mapRequesterBalances[requester] = 0;

        // Burn requester credit balance
        IERC1155(subscriptionNFT).burn(requester, subscriptionTokenId, balance);

        emit RequesterCreditsRedeemed(requester, balance);

        _locked = 1;
    }
}