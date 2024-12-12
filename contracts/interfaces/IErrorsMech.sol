// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IErrorsMech {
    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev Provided zero value.
    error ZeroValue();

    /// @dev Only `marketplace` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param manager Required sender address as a manager.
    error MarketplaceOnly(address sender, address manager);

    /// @dev Mech marketplace exists.
    /// @param mechMarketplace Mech marketplace address.
    error MarketplaceExists(address mechMarketplace);

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

    /// @dev Caught reentrancy violation.
    error ReentrancyGuard();

    /// @dev Wrong state of a service.
    /// @param state Service state.
    /// @param serviceId Service Id.
    error WrongServiceState(uint256 state, uint256 serviceId);
}
