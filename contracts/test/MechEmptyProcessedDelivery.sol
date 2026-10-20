// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MechFixedPriceNative} from "../mechs/native/MechFixedPriceNative.sol";
import {MechFactoryFixedPriceNative} from "../mechs/native/MechFactoryFixedPriceNative.sol";

/// @dev Test-only mech whose preprocessing returns an empty response for nonempty input.
contract MechEmptyProcessedDelivery is MechFixedPriceNative {
    constructor(address marketplace, address registry, uint256 service, uint256 rate)
        MechFixedPriceNative(marketplace, registry, service, rate)
    {}

    function _preDeliver(bytes32, bytes calldata)
        internal pure override returns (bytes memory deliveryData, uint256 deliveryRate)
    {
        return ("", 100);
    }
}

contract MechFactoryEmptyProcessedDelivery is MechFactoryFixedPriceNative {
    constructor(address marketplace) MechFactoryFixedPriceNative(marketplace) {}

    function _createMechWithSalt(bytes32 salt, address marketplace, address registry, uint256 service, uint256 rate)
        internal override returns (address)
    {
        return address(new MechEmptyProcessedDelivery{salt: salt}(marketplace, registry, service, rate));
    }
}
