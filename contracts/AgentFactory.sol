// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AgentMech} from "./AgentMech.sol";
import {GenericManager} from "../lib/autonolas-registries/contracts/GenericManager.sol";

interface IAgentRegistry {
    /// @dev Creates a agent.
    /// @param agentOwner Owner of the agent.
    /// @param agentHash IPFS CID hash of the agent metadata.
    /// @return agentId The id of a minted agent.
    function create(address agentOwner, bytes32 agentHash) external returns (uint256 agentId);
}

/// @title Agent Factory - Periphery smart contract for managing agent and mech creation
contract AgentFactory is GenericManager {
    event CreateMech(address indexed mech, uint256 indexed agentId, uint256 indexed price);

    // Agent factory version number
    string public constant VERSION = "1.0.0";

    // Agent registry address
    address public immutable agentRegistry;

    constructor(address _agentRegistry) {
        agentRegistry = _agentRegistry;
        owner = msg.sender;
    }

    /// @dev Creates agent.
    /// @param agentOwner Owner of the agent.
    /// @param agentHash IPFS CID hash of the agent metadata.
    /// @param price Minimum required payment the agent accepts.
    /// @return agentId The id of a created agent.
    /// @return mech The created mech instance address.
    function create(
        address agentOwner,
        bytes32 agentHash,
        uint256 price
    ) external returns (uint256 agentId, address mech)
    {
        // Check if the creation is paused
        if (paused) {
            revert Paused();
        }

        agentId = IAgentRegistry(agentRegistry).create(agentOwner, agentHash);
        bytes32 salt = keccak256(abi.encode(agentOwner, agentId));
        // agentOwner is isOperator() for the mech
        mech = address((new AgentMech){salt: salt}(agentRegistry, agentId, price));
        emit CreateMech(mech, agentId, price);
    }
}
