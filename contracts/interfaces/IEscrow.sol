// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Escrow interface
interface IEscrow {
    // Check and escrow delivery rate
    function checkAndEscrowDeliveryRate(address mech) external payable;

    function adjustBalances(address mech, uint256 mechPayment, uint256 marketplaceFee) external;
}