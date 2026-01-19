// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MechFixedPriceBase} from "../../../MechFixedPriceBase.sol";

/// @title MechFixedPriceToken - Smart contract for OlasMech that accepts a fixed price payment for services in native token.
contract MechFixedPriceTokenUSDC is MechFixedPriceBase {
    // keccak256(FixedPriceTokenUSDC) = 6406bb5f31a732f898e1ce9fdd988a80a808d36ab5d9a4a4805a8be8d197d5e3
    bytes32 public constant PAYMENT_TYPE = 0x6406bb5f31a732f898e1ce9fdd988a80a808d36ab5d9a4a4805a8be8d197d5e3;

    /// @dev MechFixedPriceToken constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _serviceRegistry Address of the token contract.
    /// @param _serviceId Service Id.
    /// @param _maxDeliveryRate The maximum delivery rate.
    constructor(address _mechMarketplace, address _serviceRegistry, uint256 _serviceId, uint256 _maxDeliveryRate)
        MechFixedPriceBase(_mechMarketplace, _serviceRegistry, _serviceId, _maxDeliveryRate, PAYMENT_TYPE)
    {}
}
