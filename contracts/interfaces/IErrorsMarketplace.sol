// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IErrorsMarketplace {
    /// @dev Only `owner` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param owner Required sender address as an owner.
    error OwnerOnly(address sender, address owner);

    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev Provided zero value.
    error ZeroValue();

    /// @dev The contract is already initialized.
    error AlreadyInitialized();

    /// @dev Wrong length of two arrays.
    /// @param numValues1 Number of values in a first array.
    /// @param numValues2 Number of values in a second array.
    error WrongArrayLength(uint256 numValues1, uint256 numValues2);

    /// @dev Wrong length of three arrays.
    /// @param numValues1 Number of values in a first array.
    /// @param numValues2 Number of values in a second array.
    /// @param numValues3 Number of values in a third array.
    error WrongArrayLength3(uint256 numValues1, uint256 numValues2, uint256 numValues3);

    /// @dev Wrong length of four arrays.
    /// @param numValues1 Number of values in a first array.
    /// @param numValues2 Number of values in a second array.
    /// @param numValues3 Number of values in a third array.
    /// @param numValues4 Number of values in a fourth array.
    error WrongArrayLength4(uint256 numValues1, uint256 numValues2, uint256 numValues3, uint256 numValues4);

    /// @dev Not enough balance to cover costs.
    /// @param current Current balance.
    /// @param required Required balance.
    error InsufficientBalance(uint256 current, uint256 required);

    /// @dev No incoming msg.value is allowed.
    /// @param amount Value amount.
    error NoDepositAllowed(uint256 amount);

    /// @dev Request Id not found.
    /// @param requestId Request Id.
    error RequestIdNotFound(bytes32 requestId);

    /// @dev Value overflow.
    /// @param provided Overflow value.
    /// @param max Maximum possible value.
    error Overflow(uint256 provided, uint256 max);

    /// @dev Caught reentrancy violation.
    error ReentrancyGuard();

    /// @dev Account is unauthorized.
    /// @param account Account address.
    error UnauthorizedAccount(address account);

    /// @dev Specified service Id is not staked.
    /// @param stakingInstance Staking contract instance.
    /// @param serviceId Service Id.
    error ServiceNotStaked(address stakingInstance, uint256 serviceId);

    /// @dev Wrong state of a service.
    /// @param state Service state.
    /// @param serviceId Service Id.
    error WrongServiceState(uint256 state, uint256 serviceId);

    /// @dev Provided value is out of bounds.
    /// @param provided value.
    /// @param min Minimum possible value.
    /// @param max Maximum possible value.
    error OutOfBounds(uint256 provided, uint256 min, uint256 max);

    /// @dev The request is already requested.
    /// @param requestId Request Id.
    error AlreadyRequested(bytes32 requestId);

    /// @dev The request is already delivered.
    /// @param requestId Request Id.
    error AlreadyDelivered(bytes32 requestId);

    /// @dev Wrong payment type.
    /// @param paymentType Payment type.
    error WrongPaymentType(bytes32 paymentType);

    /// @dev Failure of a transfer.
    /// @param token Address of a token.
    /// @param from Address `from`.
    /// @param to Address `to`.
    /// @param amount Amount value.
    error TransferFailed(address token, address from, address to, uint256 amount);

    /// @dev Incorrect signature length provided.
    /// @param signature Signature bytes.
    /// @param provided Provided signature length.
    /// @param expected Expected signature length.
    error IncorrectSignatureLength(bytes signature, uint256 provided, uint256 expected);

    /// @dev Hash signature is not validated.
    /// @param requester Requester contract address.
    /// @param msgHash Message hash.
    /// @param signature Signature bytes associated with the message hash.
    error SignatureNotValidated(address requester, bytes32 msgHash, bytes signature);
}
