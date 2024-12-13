// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Agent Mech interface
interface IMech {
    /// @dev Checks if the signer is the mech operator.
    function isOperator(address signer) external view returns (bool);

    /// @dev Registers a request by a marketplace.
    /// @param account Requester account address.
    /// @param payment Supplied request payment.
    /// @param data Self-descriptive opaque data-blob.
    /// @param requestId Request Id.
    function requestFromMarketplace(address account, uint256 payment, bytes memory data, uint256 requestId) external;

    /// @dev Revokes the request from the mech that does not deliver it.
    /// @notice Only marketplace can call this function if the request is not delivered by the chosen priority mech.
    /// @param requestId Request Id.
    function revokeRequest(uint256 requestId) external;

    /// @dev Validates agent mech.
    /// @param agentMech Agent mech address.
    /// @return status True, if the mech is valid.
    function checkMechValidity(address agentMech) external view returns (bool status);
}