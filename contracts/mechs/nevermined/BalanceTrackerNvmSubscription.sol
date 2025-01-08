// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMech} from "../../interfaces/IMech.sol";

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
}

/// @dev Only `marketplace` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param marketplace Required marketplace address.
error MarketplaceOnly(address sender, address marketplace);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Not enough balance to cover costs.
/// @param current Current balance.
/// @param required Required balance.
error InsufficientBalance(uint256 current, uint256 required);

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev No incoming msg.value is allowed.
/// @param amount Value amount.
error NoDepositAllowed(uint256 amount);

contract BalanceTrackerNvmSubscription {
    event MechPaymentCalculated(address indexed mech, uint256 indexed requestId, uint256 deliveryRate, uint256 rateDiff);
    event CreditsAccounted(address indexed account, uint256 amount);

    // Mech marketplace address
    address public immutable mechMarketplace;
    // Subscription NFT
    address public immutable subscriptionNFT;
    // Subscription token Id
    uint256 public immutable subscriptionTokenId;

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Map of requester => current credit balance
    mapping(address => uint256) public mapRequesterBalances;
    // Map of mech => current debit balance
    mapping(address => uint256) public mapMechBalances;

    /// @dev BalanceTrackerSubscription constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _subscriptionNFT Subscription NFT address.
    /// @param _subscriptionTokenId Subscription token Id.
    constructor(address _mechMarketplace, address _subscriptionNFT, uint256 _subscriptionTokenId) {
        if (_subscriptionNFT == address(0)) {
            revert ZeroAddress();
        }

        if (_subscriptionTokenId == 0) {
            revert ZeroValue();
        }

        mechMarketplace = _mechMarketplace;
        subscriptionNFT = _subscriptionNFT;
        subscriptionTokenId = _subscriptionTokenId;
    }

    /// @dev Checks and records delivery rate.
    /// @param requester Requester address.
    /// @param maxDeliveryRate Request max delivery rate.
    function checkAndRecordDeliveryRate(
        address requester,
        uint256 maxDeliveryRate,
        bytes memory
    ) external payable {
        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceOnly(msg.sender, mechMarketplace);
        }

        // Check that there is no incoming deposit
        if (msg.value > 0) {
            revert NoDepositAllowed(msg.value);
        }

        // Get requester credit balance
        uint256 balance = mapRequesterBalances[requester];
        // Get requester actual subscription balance
        uint256 subscriptionBalance = IERC1155(subscriptionNFT).balanceOf(requester, subscriptionTokenId);

        // Adjust requester balance with maxDeliveryRate credits
        balance += maxDeliveryRate;

        // Check the request delivery rate for a fixed price
        if (subscriptionBalance < balance) {
            revert InsufficientBalance(subscriptionBalance, balance);
        }

        // Adjust requester balance
        mapRequesterBalances[requester] = balance;
    }

    /// @dev Finalizes mech delivery rate based on requested and actual ones.
    /// @param mech Delivery mech address.
    /// @param requester Requester address.
    /// @param requestId Request Id.
    /// @param maxDeliveryRate Requested max delivery rate.
    function finalizeDeliveryRate(address mech, address requester, uint256 requestId, uint256 maxDeliveryRate) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceOnly(msg.sender, mechMarketplace);
        }

        // Get actual delivery rate
        uint256 actualDeliveryRate = IMech(mech).getFinalizedDeliveryRate(requestId);

        // Check for zero value
        if (actualDeliveryRate == 0) {
            revert ZeroValue();
        }

        uint256 rateDiff;
        if (maxDeliveryRate > actualDeliveryRate) {
            // Return back requester overpayment credit
            rateDiff = maxDeliveryRate - actualDeliveryRate;

            // Get requester balance
            uint256 balance = mapRequesterBalances[requester];

            // This must never happen as max delivery rate is always bigger or equal to the actual delivery rate
            if (rateDiff > balance) {
                revert Overflow(rateDiff, balance);
            }

            // Adjust requester balance
            balance -= rateDiff;
            mapRequesterBalances[requester] = balance;
        } else {
            actualDeliveryRate = maxDeliveryRate;
        }

        // Record payment into mech balance
        mapMechBalances[mech] += actualDeliveryRate;

        emit MechPaymentCalculated(mech, requestId, actualDeliveryRate, rateDiff);

        _locked = 1;
    }

    /// @dev Processes requester credits.
    /// @param requester Requester address.
    function processPayment(address requester) external {
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

        emit CreditsAccounted(requester, balance);

        _locked = 1;
    }
}