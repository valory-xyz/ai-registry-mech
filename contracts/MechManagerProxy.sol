// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero implementation address.
error ZeroImplementationAddress();

/// @dev Zero mechManager data.
error ZeroMechManagerData();

/// @dev Proxy initialization failed.
error InitializationFailed();

/*
* This is a MechManager proxy contract.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special mechManager implementation address slot is produced by hashing the "MECH_MANAGER_PROXY"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title MechManagerProxy - Smart contract for mech manager proxy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract MechManagerProxy {
    // Code position in storage is keccak256("MECH_MANAGER_PROXY") = "0x4d988168e3618e8ed79943415869916bdedf776fc6197c43f9336905a622dab2"
    bytes32 public constant MECH_MANAGER_PROXY = 0x4d988168e3618e8ed79943415869916bdedf776fc6197c43f9336905a622dab2;

    /// @dev MechManagerProxy constructor.
    /// @param implementation MechManager implementation address.
    /// @param mechManagerData MechManager initialization data.
    constructor(address implementation, bytes memory mechManagerData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (implementation == address(0)) {
            revert ZeroImplementationAddress();
        }

        // Check for the zero data
        if (mechManagerData.length == 0) {
            revert ZeroMechManagerData();
        }

        // Store the mechManager implementation address
        assembly {
            sstore(MECH_MANAGER_PROXY, implementation)
        }
        // Initialize proxy tokenomics storage
        (bool success, ) = implementation.delegatecall(mechManagerData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        assembly {
            let implementation := sload(MECH_MANAGER_PROXY)
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}