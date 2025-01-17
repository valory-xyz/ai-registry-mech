// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MechFixedPriceBase} from "../../MechFixedPriceBase.sol";

/// @title MechFixedPriceNative - Smart contract for OlasMech that accepts a fixed price payment for services in native token.
contract MechFixedPriceNative is MechFixedPriceBase {
    // keccak256(FixedPriceNative) = ba699a34be8fe0e7725e93dcbce1701b0211a8ca61330aaeb8a05bf2ec7abed1
    bytes32 public constant PAYMENT_TYPE = 0xba699a34be8fe0e7725e93dcbce1701b0211a8ca61330aaeb8a05bf2ec7abed1;

    /// @dev MechFixedPriceNative constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _serviceRegistry Address of the token contract.
    /// @param _serviceId Service Id.
    /// @param _maxDeliveryRate The maximum delivery rate.
    constructor(address _mechMarketplace, address _serviceRegistry, uint256 _serviceId, uint256 _maxDeliveryRate)
        MechFixedPriceBase(_mechMarketplace, _serviceRegistry, _serviceId, _maxDeliveryRate, PAYMENT_TYPE)
    {}
}
