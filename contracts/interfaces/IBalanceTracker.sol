// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Escrow interface
interface IBalanceTracker {
    // Check and escrow delivery rate
    function checkAndRecordDeliveryRate(address mech, bytes memory paymentData) external payable;

    function adjustBalances(address mech, uint256 mechPayment, uint256 marketplaceFee) external;
}