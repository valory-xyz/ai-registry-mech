// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {GenericRegistry} from "../lib/autonolas-registries/contracts/GenericRegistry.sol";
import {ERC721} from "../lib/autonolas-registries/lib/solmate/src/tokens/ERC721.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
/// @param agentId Agent Id.
error OperatorOnly(address sender, address owner, uint256 agentId);

/// @dev Agent does not exist.
/// @param agentId Agent Id.
error AgentNotFound(uint256 agentId);

/// @title Agent Registry - Smart contract for registering agents
contract AgentRegistry is GenericRegistry {
    event CreateAgent(uint256 indexed agentId, bytes32 agentHash);
    event UpdateAgentHash(uint256 indexed agentId, bytes32 agentHash);

    // Agent registry version number
    string public constant VERSION = "1.0.0";

    // Map of agent Id => set of updated IPFS hashes
    mapping(uint256 => bytes32[]) public mapAgentIdHashes;

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

    /// @dev Creates a agent.
    /// @param agentOwner Owner of the agent.
    /// @param agentHash IPFS CID hash of the agent metadata.
    /// @return agentId The id of a minted agent.
    function create(address agentOwner, bytes32 agentHash) external returns (uint256 agentId) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a agent creation
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Checks for a non-zero owner address
        if(agentOwner == address(0)) {
            revert ZeroAddress();
        }

        // Check for the non-zero hash value
        if (agentHash == 0) {
            revert ZeroValue();
        }

        // Agent Id is derived from the totalSupply value
        agentId = totalSupply;
        // Agent with Id = 0 is left empty not to do additional checks for the index zero
        agentId++;

        // Initialize the agent and mint its token
        mapAgentIdHashes[agentId].push(agentHash);

        // Set total supply to the agent Id number
        totalSupply = agentId;
        // Safe mint is needed since contracts can create agents as well
        _safeMint(agentOwner, agentId);

        emit CreateAgent(agentId, agentHash);
        _locked = 1;
    }

    /// @dev Updates the agent hash.
    /// @param agentId Agent Id.
    /// @param agentHash Updated IPFS CID hash of the agent metadata.
    /// @return success True, if function executed successfully.
    function updateHash(uint256 agentId, bytes32 agentHash) external returns (bool success) {
        // Checking the agent ownership
        address operator = ownerOf(agentId);
        if (operator != msg.sender) {
            revert OperatorOnly(operator, msg.sender, agentId);
        }

        // Check for the hash value
        if (agentHash == 0) {
            revert ZeroValue();
        }

        mapAgentIdHashes[agentId].push(agentHash);
        success = true;

        emit UpdateAgentHash(agentId, agentHash);
    }

    /// @dev Gets agent hashes.
    /// @param agentId Agent Id.
    /// @return numHashes Number of hashes.
    /// @return agentHashes The list of agent hashes.
    function getHashes(uint256 agentId) external view returns (uint256 numHashes, bytes32[] memory agentHashes) {
        if (agentId > 0 && agentId <= totalSupply) {
            agentHashes = mapAgentIdHashes[agentId];
        } else {
            revert AgentNotFound(agentId);
        }

        return (agentHashes.length, agentHashes);
    }

    /// @dev Gets the latest agent hash for the agent Id.
    /// @notice The latest hash is going to be used by the tokenURI() function.
    /// @param agentId Agent Id.
    function _getUnitHash(uint256 agentId) internal view override returns (bytes32) {
        if (agentId > 0 && agentId <= totalSupply) {
            uint256 lastHashIdx = mapAgentIdHashes[agentId].length - 1;
            return mapAgentIdHashes[agentId][lastHashIdx];
        } else {
            revert AgentNotFound(agentId);
        }
    }
}
