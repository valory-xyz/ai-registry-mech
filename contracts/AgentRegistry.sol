// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GenericRegistry} from "../lib/autonolas-registries/contracts/GenericRegistry.sol";
import {ERC721} from "../lib/autonolas-registries/lib/solmate/src/tokens/ERC721.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
/// @param unitId Unit Id.
error OperatorOnly(address sender, address owner, uint256 unitId);

/// @dev Unit does not exist.
/// @param unitId Unit Id.
error UnitNotFound(uint256 unitId);

/// @title Agent Registry - Smart contract for registering agents
contract AgentRegistry is GenericRegistry {
    event CreateUnit(uint256 indexed unitId, bytes32 unitHash);
    event UpdateUnitHash(uint256 indexed unitId, bytes32 unitHash);

    // Agent registry version number
    string public constant VERSION = "1.0.0";

    // Map of unit Id => set of updated IPFS hashes
    mapping(uint256 => bytes32[]) public mapUnitIdHashes;

    /// @dev Agent registry constructor.
    /// @param _name Agent registry contract name.
    /// @param _symbol Agent registry contract symbol.
    /// @param _baseURI Agent registry token base URI.
    constructor(string memory _name, string memory _symbol, string memory _baseURI)
        ERC721(_name, _symbol)
    {
        baseURI = _baseURI;
        owner = msg.sender;
    }

    /// @dev Creates a unit.
    /// @param unitOwner Owner of the unit.
    /// @param unitHash IPFS CID hash of the unit.
    /// @return unitId The id of a minted unit.
    function create(address unitOwner, bytes32 unitHash) external returns (uint256 unitId) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a unit creation
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Checks for a non-zero owner address
        if(unitOwner == address(0)) {
            revert ZeroAddress();
        }

        // Check for the non-zero hash value
        if (unitHash == 0) {
            revert ZeroValue();
        }

        // Unit Id is derived from the totalSupply value
        unitId = totalSupply;
        // Unit with Id = 0 is left empty not to do additional checks for the index zero
        unitId++;

        // Initialize the unit and mint its token
        mapUnitIdHashes[unitId].push(unitHash);

        // Set total supply to the unit Id number
        totalSupply = unitId;
        // Safe mint is needed since contracts can create units as well
        _safeMint(unitOwner, unitId);

        emit CreateUnit(unitId, unitHash);
        _locked = 1;
    }

    /// @dev Updates the unit hash.
    /// @param unitOwner Owner of the unit.
    /// @param unitId Unit Id.
    /// @param unitHash Updated IPFS hash of the unit.
    /// @return success True, if function executed successfully.
    function updateHash(address unitOwner, uint256 unitId, bytes32 unitHash) external returns (bool success) {
        // Checking the unit ownership
        address operator = ownerOf(unitId);
        if (operator != unitOwner) {
            revert OperatorOnly(operator, unitOwner, unitId);
        }

        // Check for the hash value
        if (unitHash == 0) {
            revert ZeroValue();
        }

        mapUnitIdHashes[unitId].push(unitHash);
        success = true;

        emit UpdateUnitHash(unitId, unitHash);
    }

    /// @dev Gets unit hashes.
    /// @param unitId Unit Id.
    /// @return numHashes Number of hashes.
    /// @return unitHashes The list of unit hashes.
    function getHashes(uint256 unitId) external view returns (uint256 numHashes, bytes32[] memory unitHashes) {
        if (unitId > 0 && unitId <= totalSupply) {
            unitHashes = mapUnitIdHashes[unitId];
        } else {
            revert UnitNotFound(unitId);
        }

        return (unitHashes.length, unitHashes);
    }

    /// @dev Gets the original unit hash for the unit Id.
    /// @notice The original hash is going to be used by the tokenURI() function.
    /// @param unitId Unit Id.
    function _getUnitHash(uint256 unitId) internal view override returns (bytes32) {
        if (unitId > 0 && unitId <= totalSupply) {
            uint256 lastHashIdx = mapUnitIdHashes[unitId].length - 1;
            return mapUnitIdHashes[unitId][lastHashIdx];
        } else {
            revert UnitNotFound(unitId);
        }
    }
}
