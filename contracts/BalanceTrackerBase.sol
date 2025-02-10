// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMech {
    /// @dev Checks the mech operator (service multisig).
    /// @param multisig Service multisig being checked against.
    /// @return True, if mech service multisig matches the provided one.
    function isOperator(address multisig) external view returns (bool);
}

interface IMechMarketplace {
    /// @dev Gets Mech Marketplace fee.
    /// @return Mech Marketplace fee.
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

/// @title BalanceTrackerBase - abstract contract for tracking mech and requester balances
abstract contract BalanceTrackerBase {
    event RequesterBalanceAdjusted(address indexed requester, uint256 deliveryRate, uint256 balance);
    event MechBalanceAdjusted(address indexed mech, uint256 deliveryRate, uint256 balance, uint256 rateDiff);
    event Deposit(address indexed account, address indexed token, uint256 amount);
    event Withdraw(address indexed account, address indexed token, uint256 amount);
    event Drained(address indexed token, uint256 collectedFees);

    // Max marketplace fee factor (100%)
    uint256 public constant MAX_FEE_FACTOR = 10_000;
    // Min mech balance
    uint256 public constant MIN_MECH_BALANCE = 2;

    // Mech marketplace address
    address public immutable mechMarketplace;
    // Drainer address
    address public immutable drainer;
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
    /// @param _drainer Drainer address.
    constructor(address _mechMarketplace, address _drainer) {
        // Check for zero address
        if (_mechMarketplace == address(0) || _drainer == address(0)) {
            revert ZeroAddress();
        }

        mechMarketplace = _mechMarketplace;
        drainer = _drainer;
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

            // Check if updated balance is still insufficient
            if (balance < deliveryRate) {
                revert InsufficientBalance(balance, deliveryRate);
            }
        }

        // Adjust account balance
        return (balance - deliveryRate);
    }

    /// @dev Adjusts final requester balance accounting for possible delivery rate difference (debit).
    /// @param requesterBalance Requester balance.
    /// @param rateDiff Delivery rate difference.
    /// @return Adjusted balance.
    function _adjustFinalBalance(uint256 requesterBalance, uint256 rateDiff) internal virtual returns (uint256) {
        return requesterBalance + rateDiff;
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
        if (balance < MIN_MECH_BALANCE) {
            revert ZeroValue();
        }

        // Calculate mech payment and marketplace fee
        uint256 fee = _getFee();

        // If requested balance is too small, charge the minimal fee
        // ceil(a, b) = (a + b - 1) / b
        // This formula will always get at least a fee of 1
        marketplaceFee = (balance * fee + (MAX_FEE_FACTOR - 1)) / MAX_FEE_FACTOR;

        // Calculate mech payment
        mechPayment = balance - marketplaceFee;

        // Check for zero value, although this must never happen
        if ((fee > 0 && marketplaceFee == 0) || mechPayment == 0) {
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
    /// @param numRequests Number of requests.
    /// @param deliveryRate Single request delivery rate.
    /// @param paymentData Additional payment-related request data, if applicable.
    function checkAndRecordDeliveryRates(
        address requester,
        uint256 numRequests,
        uint256 deliveryRate,
        bytes calldata paymentData
    ) external virtual payable {
        // Reentrancy guard
        if (_locked == 2) {
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

        // Total requester delivery rate is number of requests coming to a selected mech
        uint256 totalDeliveryRate = deliveryRate * numRequests;

        // Adjust account balance
        balance = _adjustInitialBalance(requester, balance, totalDeliveryRate, paymentData);
        mapRequesterBalances[requester] = balance;

        emit RequesterBalanceAdjusted(requester, totalDeliveryRate, balance);

        _locked = 1;
    }

    /// @dev Finalizes mech delivery rate based on requested and actual ones.
    /// @param mech Delivery mech address.
    /// @param requesters Requester addresses.
    /// @param deliveredRequests Set of mech request Id statuses: delivered / undelivered.
    /// @param mechDeliveryRates Corresponding set of actual charged delivery rates for each request.
    /// @param requesterDeliveryRates Corresponding set of requester agreed delivery rates for each request.
    function finalizeDeliveryRates(
        address mech,
        address[] calldata requesters,
        bool[] calldata deliveredRequests,
        uint256[] calldata mechDeliveryRates,
        uint256[] calldata requesterDeliveryRates
    ) external virtual {
        // Reentrancy guard
        if (_locked == 2) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceOnly(msg.sender, mechMarketplace);
        }

        // Get total mech and requester delivery rates
        uint256 totalMechDeliveryRate;
        uint256 totalRateDiff;
        for (uint256 i = 0; i < deliveredRequests.length; ++i) {
            // Check if request was delivered
            if (deliveredRequests[i]) {
                totalMechDeliveryRate += mechDeliveryRates[i];

                // Check for delivery rate difference
                if (requesterDeliveryRates[i] > mechDeliveryRates[i]) {
                    // Return back requester overpayment debit / credit
                    uint256 rateDiff = requesterDeliveryRates[i] - mechDeliveryRates[i];
                    totalRateDiff += rateDiff;

                    // Adjust requester balance
                    uint256 requesterBalance = mapRequesterBalances[requesters[i]];
                    mapRequesterBalances[requesters[i]] = _adjustFinalBalance(requesterBalance, rateDiff);
                }
            }
        }

        // Check for zero value
        if (totalMechDeliveryRate == 0) {
            revert ZeroValue();
        }

        // Record payment into mech balance
        uint256 mechBalance = mapMechBalances[mech];
        mechBalance += totalMechDeliveryRate;
        mapMechBalances[mech] = mechBalance;

        emit MechBalanceAdjusted(mech, totalMechDeliveryRate, mechBalance, totalRateDiff);

        _locked = 1;
    }

    /// @dev Adjusts mech and requester balances for direct batch request processing.
    /// @notice This function can be called by the Mech Marketplace only.
    /// @param mech Mech address.
    /// @param requester Requester address.
    /// @param mechDeliveryRates Set of actual charged delivery rates for each request.
    /// @param paymentData Additional payment-related request data, if applicable.
    function adjustMechRequesterBalances(
        address mech,
        address requester,
        uint256[] calldata mechDeliveryRates,
        bytes calldata paymentData
    ) external virtual {
        // Reentrancy guard
        if (_locked == 2) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceOnly(msg.sender, mechMarketplace);
        }

        // Get total mech delivery rate
        uint256 totalMechDeliveryRate;
        for (uint256 i = 0; i < mechDeliveryRates.length; ++i) {
            totalMechDeliveryRate += mechDeliveryRates[i];
        }

        // Check for zero value
        if (totalMechDeliveryRate == 0) {
            revert ZeroValue();
        }

        // Get requester balance
        uint256 requesterBalance = mapRequesterBalances[requester];
        // Adjust requester balance
        requesterBalance = _adjustInitialBalance(requester, requesterBalance, totalMechDeliveryRate, paymentData);
        mapRequesterBalances[requester] = requesterBalance;

        // Record payment into mech balance
        uint256 mechBalance = mapMechBalances[mech];
        mechBalance += totalMechDeliveryRate;
        mapMechBalances[mech] = mechBalance;

        emit RequesterBalanceAdjusted(requester, totalMechDeliveryRate, requesterBalance);
        emit MechBalanceAdjusted(mech, totalMechDeliveryRate, mechBalance, 0);

        _locked = 1;
    }

    /// @dev Drains collected fees by sending them to a drainer contract.
    function drain() external {
        // Reentrancy guard
        if (_locked == 2) {
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
        if (_locked == 2) {
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
        if (_locked == 2) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        (mechPayment, marketplaceFee) = _processPayment(msg.sender);

        _locked = 1;
    }
}