// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockMech} from "./MockMech.sol";

/// @dev Incorrect data length.
/// @param provided Provided data length.
/// @param expected Expected data length.
error IncorrectDataLength(uint256 provided, uint256 expected);

/// @dev Only `marketplace` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param marketplace Required marketplace address.
error MarketplaceOnly(address sender, address marketplace);

/// @dev Provided zero address.
error ZeroAddress();

/// @title MockMechFactory - Periphery smart contract for managing mock mech creation
contract MockMechFactory {
    event CreateMockMech(address indexed mech, uint256 maxDeliveryRate);

    // Agent factory version number
    string public constant VERSION = "0.1.0";
    // Mech marketplace address
    address public immutable mechMarketplace;

    // Decode max delivery rate
    uint256 public maxDeliveryRate = 1;

    // Nonce
    uint256 internal _nonce;

    /// @dev MechFactoryFixedPriceNative constructor.
    /// @param _mechMarketplace Mech marketplace address.
    constructor(address _mechMarketplace) {
        mechMarketplace = _mechMarketplace;
    }

    /// @dev Registers service as a mech.
    /// @return mech The created mech instance address.
    function createMech(
        address,
        uint256,
        bytes memory
    ) external returns (address mech) {
        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceOnly(msg.sender, mechMarketplace);
        }

        uint256 localNonce = _nonce;
        // Get salt
        bytes32 salt = keccak256(abi.encode(block.timestamp, msg.sender, localNonce));
        _nonce = localNonce + 1;

        // Service multisig is isOperator() for the mech
        mech = address((new MockMech){salt: salt}(mechMarketplace));

        // Check for zero address
        if (mech == address(0)) {
            revert ZeroAddress();
        }

        emit CreateMockMech(mech, maxDeliveryRate);
    }
}
