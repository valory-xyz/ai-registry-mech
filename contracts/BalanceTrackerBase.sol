// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMech} from "./interfaces/IMech.sol";

interface IMechMarketplace {
    function fee() external view returns(uint256);
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

abstract contract BalanceTrackerBase {
    event RequesterBalanceAdjusted(address indexed requester, uint256 deliveryRate, uint256 balance);
    event MechBalanceAdjusted(address indexed mech, uint256 deliveryRate, uint256 balance);
    event MechPaymentCalculated(address indexed mech, uint256 indexed requestId, uint256 deliveryRate, uint256 rateDiff);
    event Deposit(address indexed account, address indexed token, uint256 amount);
    event Withdraw(address indexed account, address indexed token, uint256 amount);
    event Drained(address indexed token, uint256 collectedFees);

    // Max marketplace fee factor (100%)
    uint256 public constant MAX_FEE_FACTOR = 10_000;

    // Mech marketplace address
    address public immutable mechMarketplace;
    // Buy back burner address
    address public immutable buyBackBurner;
    // Collected fees
    uint256 public collectedFees;
    // Reentrancy lock
    uint256 internal _locked = 1;

    // Map of requester => current balance
    mapping(address => uint256) public mapRequesterBalances;
    // Map of mech => => current balance
    mapping(address => uint256) public mapMechBalances;

    /// @dev BalanceTrackerFixedPrice constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _buyBackBurner Buy back burner address.
    constructor(address _mechMarketplace, address _buyBackBurner) {
        // Check for zero address
        if (_mechMarketplace == address(0) || _buyBackBurner == address(0)) {
            revert ZeroAddress();
        }

        mechMarketplace = _mechMarketplace;
        buyBackBurner = _buyBackBurner;
    }

    /// @dev Adjusts initial requester balance accounting for delivery rate (debit).
    /// @param balance Initial requester balance.
    /// @param deliveryRate Delivery rate.
    function _adjustInitialBalance(
        address requester,
        uint256 balance,
        uint256 deliveryRate,
        bytes memory
    ) internal virtual returns (uint256) {
        // Check the request delivery rate for a fixed price
        if (balance < deliveryRate) {
            // Get balance difference
            uint256 balanceDiff = deliveryRate - balance;
            // Adjust balance
            balance += _getRequiredFunds(requester, balanceDiff);
        }

        if (balance < deliveryRate) {
            revert InsufficientBalance(balance, deliveryRate);
        }

        // Adjust account balance
        return (balance - deliveryRate);
    }

    /// @dev Adjusts final requester balance accounting for possible delivery rate difference (debit).
    /// @param requester Requester address.
    /// @param rateDiff Delivery rate difference.
    /// @return Adjusted balance.
    function _adjustFinalBalance(address requester, uint256 rateDiff) internal virtual returns (uint256) {
        return mapRequesterBalances[requester] + rateDiff;
    }

    /// @dev Drains specified amount.
    /// @param amount Amount value.
    function _drain(uint256 amount) internal virtual;

    /// @dev Gets fee composed of marketplace fee and another one, if applicable.
    function _getFee() internal view virtual returns (uint256) {
        return IMechMarketplace(mechMarketplace).fee();
    }

    /// @dev Gets native token value or restricts receiving one.
    /// @return Received value.
    function _getOrRestrictNativeValue() internal virtual returns (uint256);

    /// @dev Gets required token funds.
    /// @param requester Requester address.
    /// @param amount Token amount.
    /// @return Received amount.
    function _getRequiredFunds(address requester, uint256 amount) internal virtual returns (uint256);

    /// @dev Process mech payment.
    /// @param mech Mech address.
    /// @return mechPayment Mech payment.
    /// @return marketplaceFee Marketplace fee.
    function _processPayment(address mech) internal virtual returns (uint256 mechPayment, uint256 marketplaceFee) {
        // Get mech balance
        uint256 balance = mapMechBalances[mech];
        // If balance is 1, the marketplace fee is still 1, and thus mech payment will be zero
        if (balance < 2) {
            revert ZeroValue();
        }

        // TODO Separate between total fee and marketplace fee when NVM solution is ready
        // Calculate mech payment and marketplace fee
        uint256 fee = _getFee();

        // If requested balance is too small, charge the minimal fee
        // ceil(a, b) = (a + b - 1) / b
        // This formula will always get at least a fee of 1
        marketplaceFee = (balance * fee + (MAX_FEE_FACTOR - 1)) / MAX_FEE_FACTOR;

        // Calculate mech payment
        mechPayment = balance - marketplaceFee;

        // TODO If fee is charged beforehand, this is irrelevant
        // Check for zero value, although this must never happen
        if (marketplaceFee == 0 || mechPayment == 0) {
            revert ZeroValue();
        }

        // Adjust marketplace fee
        collectedFees += marketplaceFee;

        // Clear balances
        mapMechBalances[mech] = 0;

        // Process withdraw
        _withdraw(mech, mechPayment);
    }

    /// @dev Withdraws funds.
    /// @param account Account address.
    /// @param amount Token amount.
    function _withdraw(address account, uint256 amount) internal virtual;

    /// @dev Checks and records delivery rate.
    /// @param requester Requester address.
    /// @param maxDeliveryRate Request max delivery rate.
    /// @param paymentData Additional payment-related request data, if applicable.
    function checkAndRecordDeliveryRate(
        address requester,
        uint256 maxDeliveryRate,
        bytes memory paymentData
    ) public payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceOnly(msg.sender, mechMarketplace);
        }

        // Check for native value
        uint256 initAmount = _getOrRestrictNativeValue();

        // Get account balance
        uint256 balance = mapRequesterBalances[requester] + initAmount;

        // Adjust account balance
        balance = _adjustInitialBalance(requester, balance, maxDeliveryRate, paymentData);
        mapRequesterBalances[requester] = balance;

        emit RequesterBalanceAdjusted(requester, maxDeliveryRate, balance);

        _locked = 1;
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

        // Check for delivery rate difference
        uint256 rateDiff;
        uint256 balance;
        if (maxDeliveryRate > actualDeliveryRate) {
            // Return back requester overpayment debit / credit
            rateDiff = maxDeliveryRate - actualDeliveryRate;

            // Adjust requester balance
            balance = _adjustFinalBalance(requester, rateDiff);
            mapRequesterBalances[requester] = balance;
        } else {
            // Limit the rate by the max chosen one as that is what the requester agreed on
            actualDeliveryRate = maxDeliveryRate;
        }

        // Record payment into mech balance
        balance = mapMechBalances[mech];
        balance += actualDeliveryRate;
        mapMechBalances[mech] = balance;

        emit MechPaymentCalculated(mech, requestId, actualDeliveryRate, rateDiff);
        emit MechBalanceAdjusted(mech, actualDeliveryRate, balance);

        _locked = 1;
    }

    /// @dev Adjusts requester and mech balances for direct batch request processing.
    /// @param mech Mech address.
    /// @param requester Requester address.
    /// @param totalDeliveryRate Total batch delivery rate.
    /// @param paymentData Additional payment-related request data, if applicable.
    function adjustRequesterMechBalances(
        address mech,
        address requester,
        uint256 totalDeliveryRate,
        bytes memory paymentData
    ) external payable {
        checkAndRecordDeliveryRate(requester, totalDeliveryRate, paymentData);

        // Record payment into mech balance
        uint256 balance = mapMechBalances[mech];
        balance += totalDeliveryRate;
        mapMechBalances[mech] = balance;

        emit MechBalanceAdjusted(mech, totalDeliveryRate, balance);
    }

    /// @dev Drains collected fees by sending them to a Buy back burner contract.
    function drain() external {
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

        // Drain
        _drain(localCollectedFees);

        _locked = 1;
    }

    /// @dev Processes mech payment by mech service multisig.
    /// @param mech Mech address.
    /// @return mechPayment Mech payment.
    /// @return marketplaceFee Marketplace fee.
    function processPaymentByMultisig(address mech) external returns (uint256 mechPayment, uint256 marketplaceFee) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for mech service multisig address
        if (!IMech(mech).isOperator(msg.sender)) {
            revert UnauthorizedAccount(msg.sender);
        }

        (mechPayment, marketplaceFee) = _processPayment(mech);

        _locked = 1;
    }

    /// @dev Processes mech payment.
    /// @return mechPayment Mech payment.
    /// @return marketplaceFee Marketplace fee.
    function processPayment() external returns (uint256 mechPayment, uint256 marketplaceFee) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        (mechPayment, marketplaceFee) = _processPayment(msg.sender);

        _locked = 1;
    }

    /// @dev Withdraws funds for a specific requester account.
    function withdraw() external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get account balance
        uint256 balance = mapRequesterBalances[msg.sender];
        if (balance == 0) {
            revert ZeroValue();
        }

        // Clear balances
        mapRequesterBalances[msg.sender] = 0;

        // Process withdraw
        _withdraw(msg.sender, balance);

        _locked = 1;
    }
}