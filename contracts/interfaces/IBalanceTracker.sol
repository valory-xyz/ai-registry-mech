// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Escrow interface
interface IBalanceTracker {
    /// @dev Checks and records delivery rate.
    /// @param requester Requester address.
    /// @param totalDeliveryRate Total request delivery rate.
    /// @param paymentData Additional payment-related request data, if applicable.
    function checkAndRecordDeliveryRates(address requester, uint256 totalDeliveryRate,
        bytes memory paymentData) external payable;

    /// @dev Finalizes mech delivery rate based on requested and actual ones.
    /// @param mech Delivery mech address.
    /// @param requesters Requester addresses.
    /// @param deliveredRequests Set of mech request Id statuses: delivered / undelivered.
    /// @param mechDeliveryRates Corresponding set of actual charged delivery rates for each request.
    /// @param requesterDeliveryRates Corresponding set of requester agreed delivery rates for each request.
    function finalizeDeliveryRates(address mech, address[] memory requesters, bool[] memory deliveredRequests,
        uint256[] memory mechDeliveryRates, uint256[] memory requesterDeliveryRates) external;

    /// @dev Adjusts mech and requester balances for direct batch request processing.
    /// @notice This function can be called by the Mech Marketplace only.
    /// @param mech Mech address.
    /// @param requester Requester address.
    /// @param mechDeliveryRates Set of actual charged delivery rates for each request.
    /// @param paymentData Additional payment-related request data, if applicable.
    function adjustMechRequesterBalances(address mech, address requester, uint256[] memory mechDeliveryRates,
        bytes memory paymentData) external;
}