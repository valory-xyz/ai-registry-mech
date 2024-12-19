// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMech} from "./interfaces/IMech.sol";

interface IToken {
    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IWrappedToken {
    function deposit() external payable;
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

/// @dev Payload length is incorrect.
/// @param provided Provided payload length.
/// @param expected Expected payload length.
error InvalidPayloadLength(uint256 provided, uint256 expected);

/// @dev Failure of a transfer.
/// @param token Address of a token.
/// @param from Address `from`.
/// @param to Address `to`.
/// @param amount Amount value.
error TransferFailed(address token, address from, address to, uint256 amount);

contract BalanceTrackerFixedPrice {
    event MechPaymentCalculated(address indexed mech, uint256 indexed requestId, uint256 deliveryRate);
    event Deposit(address indexed account, address indexed token, uint256 amount);
    event Withdraw(address indexed account, address indexed token, uint256 amount);
    event Drained(address indexed token, uint256 collectedFees);

    // Mech marketplace address
    address public immutable mechMarketplace;
    // Wrapped native token address
    address public immutable wrappedNativeToken;
    // Buy back burner address
    address public immutable buyBackBurner;
    // Payment type
    uint8 public immutable paymentType;

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Map of account => map of (token => current balance)
    mapping(address => mapping(address => uint256)) public mapAccountBalances;
    // Map of mech => its current balance
    mapping(address => mapping(address => uint256)) public mapMechBalances;
    // Map of token => collected fees
    mapping(address => uint256) public mapCollectedFees;
    // Map of requestId => token
    mapping(uint256 => address) public mapRequestIdTokens;

    /// @dev BalanceTrackerFixedPrice constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _wrappedNativeToken Wrapped native token address.
    /// @param _buyBackBurner Buy back burner address.
    /// @param _paymentType Mech payment type.
    constructor(address _mechMarketplace, address _wrappedNativeToken, address _buyBackBurner, uint8 _paymentType) {
        // Check for zero address
        if (_mechMarketplace == address(0) || _wrappedNativeToken == address(0) || _buyBackBurner == address(0)) {
            revert ZeroAddress();
        }

        mechMarketplace = _mechMarketplace;
        wrappedNativeToken = _wrappedNativeToken;
        buyBackBurner = _buyBackBurner;
        paymentType = _paymentType;
    }

    function _wrap(uint256 amount) internal virtual {
        IWrappedToken(wrappedNativeToken).deposit{value: amount}();
    }

    // Check and record delivery rate
    function checkAndRecordDeliveryRate(address mech, uint256 requestId, bytes memory paymentData) external payable {
        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert ManagerOnly(msg.sender, mechMarketplace);
        }

        // Check and record delivery rate
        uint8 mechPaymentType = IMech(mech).getPaymentType();
        // Check for payment type compatibility
        if (mechPaymentType != paymentType) {
            UnauthorizedAccount(mech);
        }

        // Get max mech delivery rate
        uint256 maxDeliveryRate = IMech(mech).maxDeliveryRate();

        // Get payment token
        address token;
        if (paymentData.length == 32) {
            // Extract token address
            token = abi.decode(paymentData, (address));
            if (token != address(0) && msg.value > 0) {
                revert NoDepositAllowed(msg.value);
            }
        } else if (paymentData.length > 0) {
            revert ();
        }

        // Get account balance
        uint256 balance = mapAccountBalances[msg.sender][token];

        // Check the request delivery rate for a fixed price
        if (balance < maxDeliveryRate) {
            revert InsufficientBalance(balance, maxDeliveryRate);
        }

        // Record request token
        mapRequestIdTokens[requestId] = token;

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

    /// @dev Finalizes mech delivery rate based on requested and actual ones.
    /// @param mech Delivery mech address.
    /// @param requester Requester address.
    /// @param requestId Request Id.
    /// @param deliveryRate Requested delivery rate.
    function finalizeDeliveryRate(address mech, address requester, uint256 requestId, uint256 deliveryRate) external {
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

        // Get token associated with request Id
        address token = mapRequestIdTokens[requestId];

        uint256 rateDiff;
        if (actualDeliveryRate > deliveryRate) {
            // Return back requester overpayment
            rateDiff = actualDeliveryRate - deliveryRate;
            mapAccountBalances[requester][token] += rateDiff;
        }

        // Record payment into mech balance
        mapMechBalances[mech] += actualDeliveryRate;

        emit MechPaymentCalculated(mech, requestId, actualDeliveryRate);
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
    function withdrawMech(address token) external returns (uint256 mechPayment, uint256 marketplaceFee) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get mech balance
        uint256 balance = mapMechBalances[msg.sender][token];
        // TODO limits?
        if (balance == 0) {
            revert ZeroValue();
        }

        // TODO apply fees
        // TODO what if fee is zero just because the delivery rate is in the order of 1..10_000?
        // Calculate mech payment and marketplace fee
        marketplaceFee = (balance * fee) / 10_000;
        mechPayment = balance - marketplaceFee;

        // Check for zero value, although this must never happen
        if (mechPayment == 0) {
            revert ZeroValue();
        }

        // Adjust marketplace fee
        mapCollectedFees[token] += marketplaceFee;

        _withdraw(token, balance);

        emit Withdraw(msg.sender, token, balance);

        _locked = 1;
    }

    /// @dev Withdraws funds for a specific account.
    function withdrawAccount(address token) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get account balance
        uint256 balance = mapAccountBalances[msg.sender][token];
        // TODO limits?
        if (balance == 0) {
            revert ZeroValue();
        }

        _withdraw(token, balance);

        emit Withdraw(msg.sender, token, balance);

        _locked = 1;
    }

    function deposit(address token, uint256 amount) external {
        // TODO Accept deposits from mechs as well?

        if (token == address(0)) {
            revert ZeroAddress();
        }

        // TODO: safe?
        IToken(token).transferFrom(msg.sender, address(0), amount);

        // Update account balances
        mapAccountBalances[msg.sender][address(0)] += msg.value;

        Deposit(msg.sender, token, msg.value);
    }

    receive() external payable {
        // TODO Accept deposits from mechs as well?

        // Update account balances
        mapAccountBalances[msg.sender][address(0)] += msg.value;

        Deposit(msg.sender, address(0), msg.value);
    }
}