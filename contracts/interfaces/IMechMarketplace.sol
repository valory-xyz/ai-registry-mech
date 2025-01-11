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

    /// @dev Delivers requests.
    /// @notice This function can only be called by the mech delivering the request.
    /// @param requestIds Set of request ids.
    /// @param mechDeliveryRates Corresponding set of actual charged delivery rates for each request.
    /// @param deliveryDatas Set of corresponding self-descriptive opaque delivery data-blobs.
    function deliverMarketplace(uint256[] memory requestIds, uint256[] memory mechDeliveryRates,
        bytes[] memory deliveryDatas) external returns (bool[] memory deliveredRequests);

    /// @dev Gets mech delivery info.
    /// @param requestId Request Id.
    /// @return Mech delivery info.
    function mapRequestIdDeliveries(uint256 requestId) external returns (MechDelivery memory);
}