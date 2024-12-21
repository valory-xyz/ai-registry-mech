// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Escrow interface
interface IBalanceTracker {
    // Check and record delivery rate
    /// @param paymentData Additional payment-related request data, if applicable.
    function checkAndRecordDeliveryRate(address mech, address requester, bytes memory paymentData) external payable;

    /// @dev Finalizes mech delivery rate based on requested and actual ones.
    /// @param mech Delivery mech address.
    /// @param requester Requester address.
    /// @param requestId Request Id.
    /// @param deliveryRate Requested delivery rate.
    function finalizeDeliveryRate(address mech, address requester, uint256 requestId, uint256 deliveryRate) external;
}