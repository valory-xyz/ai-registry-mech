// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AgentMechSubscription} from "./AgentMechSubscription.sol";

/// @title Mech Factory Subscription - Periphery smart contract for managing subscription mech creation
contract MechFactorySubscription {
    event CreateSubscriptionMech(address indexed mech, uint256 indexed serviceId, uint256 minCreditsPerRequest,
        address indexed subscriptionNFT, uint256 subscriptionTokenId);

    // Agent factory version number
    string public constant VERSION = "0.1.0";

    /// @dev Registers service as a mech.
    /// @param mechMarketplace Mech marketplace address.
    /// @param serviceRegistry Service registry address.
    /// @param serviceId Service id.
    /// @param payload Mech creation payload.
    /// @return mech The created mech instance address.
    function createMech(
        address mechMarketplace,
        address serviceRegistry,
        uint256 serviceId,
        bytes memory payload
    ) external returns (address mech) {
        // Check payload length
        if (payload.length != 96) {
            revert();
        }

        // Decode subscription parameters
        (uint256 minCreditsPerRequest, address subscriptionNFT, uint256 subscriptionTokenId) =
            abi.decode(payload, (uint256, address, uint256));

        // Get salt
        bytes32 salt = keccak256(abi.encode(block.timestamp, msg.sender, serviceId));

        // Service multisig is isOperator() for the mech
        mech = address((new AgentMechSubscription){salt: salt}(serviceRegistry, serviceId, minCreditsPerRequest,
            subscriptionNFT, subscriptionTokenId, mechMarketplace));

        emit CreateSubscriptionMech(mech, serviceId, minCreditsPerRequest, subscriptionNFT, subscriptionTokenId);
    }
}
