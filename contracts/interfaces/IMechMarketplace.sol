// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Mech Marketplace interface
interface IMechMarketplace {
    // Mech delivery info struct
    struct MechDelivery {
        // Priority mech address
        address priorityMech;
        // Delivery mech address
        address deliveryMech;
        // Requester address
        address requester;
        // Response timeout window
        uint256 responseTimeout;
        // Delivery rate
        uint256 deliveryRate;
    }

    /// @dev Delivers a request.
    /// @param requestId Request id.
    /// @param requestData Self-descriptive opaque data-blob.
    /// @param deliveryMechServiceId Mech operator service Id.
    function deliverMarketplace(
        uint256 requestId,
        bytes memory requestData,
        uint256 deliveryMechServiceId
    ) external;

    /// @dev Gets mech delivery info.
    /// @param requestId Request Id.
    /// @return Mech delivery info.
    function getMechDeliveryInfo(uint256 requestId) external returns (MechDelivery memory);
}