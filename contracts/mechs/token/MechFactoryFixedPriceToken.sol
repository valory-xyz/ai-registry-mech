// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MechFactoryBase} from "../../MechFactoryBase.sol";
import {MechFixedPriceToken} from "./MechFixedPriceToken.sol";

/// @title MechFactoryFixedPriceToken - Periphery smart contract for managing fixed price token mech creation
contract MechFactoryFixedPriceToken is MechFactoryBase {
    event CreateMechFixedPriceToken(address indexed mech, uint256 indexed serviceId, uint256 maxDeliveryRate);

    /// @dev MechFactoryFixedPriceNative constructor.
    /// @param _mechMarketplace Mech marketplace address.
    constructor(address _mechMarketplace)
        MechFactoryBase(_mechMarketplace)
    {}

    /// @dev Registers service as a mech.
    /// @param serviceRegistry Service registry address.
    /// @param serviceId Service id.
    /// @param payload Mech creation payload.
    /// @return mech The created mech instance address.
    function createMech(
        address serviceRegistry,
        uint256 serviceId,
        bytes calldata payload
    ) external returns (address mech) {
        uint256 maxDeliveryRate;
        // Create mech
        (mech, maxDeliveryRate) = _createMech(serviceRegistry, serviceId, payload);

        emit CreateMechFixedPriceToken(mech, serviceId, maxDeliveryRate);
    }

    /// @inheritdoc MechFactoryBase
    function _createMechWithSalt(
        bytes32 salt,
        address mechMarketplace,
        address serviceRegistry,
        uint256 serviceId,
        uint256 maxDeliveryRate
    ) internal virtual override returns (address mech) {
        mech = address((new MechFixedPriceToken){salt: salt}(mechMarketplace, serviceRegistry, serviceId, maxDeliveryRate));
    }
}
