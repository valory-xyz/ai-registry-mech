// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Mech Marketplace interface
interface IMechMarketplace {
    /// @dev Delivers requests.
    /// @notice This function can only be called by the mech delivering the request.
    /// @param requestIds Set of request ids.
    /// @param mechDeliveryRates Corresponding set of actual charged delivery rates for each request.
    /// @param deliveryDatas Set of corresponding self-descriptive opaque delivery data-blobs.
    function deliverMarketplace(bytes32[] memory requestIds, uint256[] memory mechDeliveryRates,
        bytes[] memory deliveryDatas) external returns (bool[] memory deliveredRequests);

    /// @dev Delivers signed requests.
    /// @notice This function must be called by mech delivering requests.
    /// @param requester Requester address.
    /// @param requestDatas Corresponding set of self-descriptive opaque request data-blobs.
    /// @param signatures Corresponding set of signatures.
    /// @param deliveryRates Corresponding set of actual charged delivery rates for each request.
    /// @param deliveryDatas Corresponding set of self-descriptive opaque delivery data-blobs.
    /// @param paymentData Additional payment-related request data, if applicable.
    function deliverMarketplaceWithSignatures(address requester, bytes[] memory requestDatas, bytes[] memory signatures,
        bytes[] memory deliveryDatas, uint256[] memory deliveryRates, bytes memory paymentData) external;
}