// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MechFixedPriceBase} from "../../MechFixedPriceBase.sol";

/// @title MechFixedPriceToken - Smart contract for OlasMech that accepts a fixed price payment for services in native token.
contract MechFixedPriceToken is MechFixedPriceBase {
    // keccak256(FixedPriceToken) = 3679d66ef546e66ce9057c4a052f317b135bc8e8c509638f7966edfd4fcf45e9
    bytes32 public constant PAYMENT_TYPE = 0x3679d66ef546e66ce9057c4a052f317b135bc8e8c509638f7966edfd4fcf45e9;

    /// @dev MechFixedPriceToken constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _serviceRegistry Address of the token contract.
    /// @param _serviceId Service Id.
    /// @param _maxDeliveryRate The maximum delivery rate.
    constructor(address _mechMarketplace, address _serviceRegistry, uint256 _serviceId, uint256 _maxDeliveryRate)
        MechFixedPriceBase(_mechMarketplace, _serviceRegistry, _serviceId, _maxDeliveryRate, PAYMENT_TYPE)
    {}
}
