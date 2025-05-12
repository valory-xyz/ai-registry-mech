// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Mech interface
interface IMech {
    /// @dev Checks the mech operator (service multisig).
    /// @param multisig Service multisig being checked against.
    /// @return True, if mech service multisig matches the provided one.
    function isOperator(address multisig) external view returns (bool);
}

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Account is unauthorized.
/// @param account Account address.
error UnauthorizedAccount(address account);

/// @title MechMetadataUpdater - Mech Metadata Updated contract to manage actual mech metadata
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract MechMetadataUpdater {
    event MetadataUpdated(address indexed mech, bytes32 indexed hash);

    // Olas mech version number
    string public constant VERSION = "0.1.0";
    // Service Registry address
    address public immutable serviceRegistry;

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Mapping of mech address => actual metadata hash
    mapping(address => bytes32) public mapMechHashes;

    /// @dev Changes mech metadata hash.
    /// @param mech Mech address.
    /// @param hash Updated metadata hash.
    function changeHash(address mech, bytes32 hash) external {
        // Reentrancy guard
        if (_locked == 2) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for mech service multisig address
        if (!IMech(mech).isOperator(msg.sender)) {
            revert UnauthorizedAccount(msg.sender);
        }

        mapMechHashes[mech] = hash;

        emit MetadataUpdated(mech, hash);

        _locked = 1;
    }
}
