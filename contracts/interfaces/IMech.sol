// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Mech interface
interface IMech {
    /// @dev Registers a request by a marketplace.
    /// @param account Requester account address.
    /// @param data Self-descriptive opaque data-blob.
    /// @param requestId Request Id.
    function requestFromMarketplace(address account, bytes memory data, uint256 requestId) external;

    /// @dev Revokes the request from the mech that does not deliver it.
    /// @notice Only marketplace can call this function if the request is not delivered by the chosen priority mech.
    /// @param requestId Request Id.
    function revokeRequest(uint256 requestId) external;

    /// @dev Gets mech max delivery rate.
    /// @return Mech maximum delivery rate.
    function maxDeliveryRate() external returns (uint256);

    /// @dev Gets mech payment type hash.
    /// @return Mech payment type hash.
    function paymentType() external returns (bytes32);

    /// @dev Gets finalized delivery rate for a request Id.
    /// @param requestId Request Id.
    /// @return Finalized delivery rate.
    function getFinalizedDeliveryRate(uint256 requestId) external returns (uint256);

    /// @dev Gets mech token Id (service Id).
    /// @return serviceId Service Id.
    function tokenId() external view returns (uint256);

    /// @dev Gets mech operator (service multisig).
    /// @return Service multisig address.
    function getOperator() external view returns (address);

    /// @dev Checks the mech operator (service multisig).
    /// @param multisig Service multisig being checked against.
    /// @return True, if mech service multisig matches the provided one.
    function isOperator(address multisig) external view returns (bool);
}