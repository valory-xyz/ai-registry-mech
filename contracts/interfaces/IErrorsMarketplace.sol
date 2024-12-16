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

    /// @dev Not enough value paid.
    /// @param provided Provided amount.
    /// @param expected Expected amount.
    error NotEnoughPaid(uint256 provided, uint256 expected);

    /// @dev Request Id not found.
    /// @param requestId Request Id.
    error RequestIdNotFound(uint256 requestId);

    /// @dev Value overflow.
    /// @param provided Overflow value.
    /// @param max Maximum possible value.
    error Overflow(uint256 provided, uint256 max);

    /// @dev Provided account is not a contract.
    /// @param account Account address.
    error NotContract(address account);

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

    /// @dev The request is already delivered.
    /// @param requestId Request Id.
    error AlreadyDelivered(uint256 requestId);

    /// @dev The request is already paid for.
    /// @param requestId Request Id.
    error RequestPaid(uint256 requestId);

    /// @dev Priority mech response timeout is not yet met.
    /// @param expected Expected timestamp.
    /// @param current Current timestamp.
    error PriorityMechResponseTimeout(uint256 expected, uint256 current);

    /// @dev Failure of a transfer.
    /// @param token Address of a token.
    /// @param from Address `from`.
    /// @param to Address `to`.
    /// @param amount Amount value.
    error TransferFailed(address token, address from, address to, uint256 amount);
}
