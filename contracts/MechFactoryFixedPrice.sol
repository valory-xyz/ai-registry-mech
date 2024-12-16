// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MechFixedPrice} from "./MechFixedPrice.sol";

/// @dev Incorrect data length.
/// @param provided Provided data length.
/// @param expected Expected data length.
error IncorrectDataLength(uint256 provided, uint256 expected);

/// @title Mech Factory Basic - Periphery smart contract for managing basic mech creation
contract MechFactoryFixedPrice {
    event CreateBasicMech(address indexed mech, uint256 indexed serviceId, uint256 indexed price);

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
        if (payload.length != 32) {
            revert IncorrectDataLength(payload.length, 32);
        }

        // Decode price
        uint256 price = abi.decode(payload, (uint256));

        // Get salt
        bytes32 salt = keccak256(abi.encode(block.timestamp, msg.sender, serviceId));

        // Service multisig is isOperator() for the mech
        mech = address((new MechFixedPrice){salt: salt}(mechMarketplace, serviceRegistry, serviceId, price));

        emit CreateBasicMech(mech, serviceId, price);
    }
}
