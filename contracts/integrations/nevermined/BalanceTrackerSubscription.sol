// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1155TokenReceiver} from "../../../lib/autonolas-registries/lib/solmate/src/tokens/ERC1155.sol";
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

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

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

/// @dev No incoming msg.value is allowed.
/// @param amount Value amount.
error NoDepositAllowed(uint256 amount);

contract BalanceTrackerSubscription is ERC1155TokenReceiver {
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

    // Check and record delivery rate
    function checkAndRecordDeliveryRate(
        address mech,
        address requester,
        uint256,
        bytes memory
    ) external payable {
        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert ManagerOnly(msg.sender, mechMarketplace);
        }

        // Get mech max delivery rate
        uint256 maxDeliveryRate = IMech(mech).maxDeliveryRate();

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
            revert ManagerOnly(msg.sender, mechMarketplace);
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
            mapRequesterBalances[requester] -= rateDiff;
        } else {
            actualDeliveryRate = maxDeliveryRate;
        }

        // Record payment into mech balance
        mapMechBalances[mech] += actualDeliveryRate;

        emit MechPaymentCalculated(mech, requestId, actualDeliveryRate, rateDiff);

        _locked = 1;
    }

    /// @dev Processes payment.
    function processPayment() external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get requester credit balance
        uint256 balance = mapRequesterBalances[msg.sender];
        // Get requester actual subscription balance
        uint256 subscriptionBalance = IERC1155(subscriptionNFT).balanceOf(msg.sender, subscriptionTokenId);

        // This must never happen
        if (subscriptionBalance < balance) {
            revert InsufficientBalance(subscriptionBalance, balance);
        }

        // Get credits to burn
        uint256 creditsToBurn = subscriptionBalance - balance;

        // TODO limits
        if (creditsToBurn == 0) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Clear balances
        mapRequesterBalances[msg.sender] = 0;

        // Burn credits of the request Id sender upon delivery
        IERC1155(subscriptionNFT).burn(msg.sender, subscriptionTokenId, creditsToBurn);

        emit CreditsAccounted(msg.sender, creditsToBurn);

        _locked = 1;
    }
}