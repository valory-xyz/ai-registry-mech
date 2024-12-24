// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IErrorsMech {
    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev Provided zero value.
    error ZeroValue();

    /// @dev The contract is already initialized.
    error AlreadyInitialized();

    /// @dev Mech marketplace is not authorized.
    /// @param mechMarketplace Mech marketplace address.
    error MarketplaceNotAuthorized(address mechMarketplace);

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
