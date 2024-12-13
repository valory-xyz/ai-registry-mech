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

    /// @dev Agent does not exist.
    /// @param agentId Agent Id.
    error AgentNotFound(uint256 agentId);

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

    /// @dev Priority mech response timeout is not yet met.
    /// @param expected Expected timestamp.
    /// @param current Current timestamp.
    error PriorityMechResponseTimeout(uint256 expected, uint256 current);
}
