// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Mech interface
interface IMech {
    enum MechType {
        FixedPrice,
        Subscription
    }

    /// @dev Checks if the signer is the mech operator.
    function isOperator(address signer) external view returns (bool);

    /// @dev Registers a request by a marketplace.
    /// @param account Requester account address.
    /// @param data Self-descriptive opaque data-blob.
    /// @param requestId Request Id.
    function requestFromMarketplace(address account, bytes memory data, uint256 requestId) external;

    /// @dev Revokes the request from the mech that does not deliver it.
    /// @notice Only marketplace can call this function if the request is not delivered by the chosen priority mech.
    /// @param requestId Request Id.
    function revokeRequest(uint256 requestId) external;

    function maxDeliveryRate() external returns (uint256);

    function mechType() external returns (MechType);

    /// @dev Gets finalized delivery rate for a request Id.
    /// @param requestId Request Id.
    /// @return Finalized delivery rate.
    function getFinalizedDeliveryRate(uint256 requestId) external returns (uint256);
}