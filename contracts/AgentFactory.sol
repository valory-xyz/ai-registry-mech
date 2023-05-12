// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AgentMech} from "./AgentMech.sol";
import {GenericManager} from "../lib/autonolas-registries/contracts/GenericManager.sol";

interface IAgentRegistry {
    /// @dev Creates a unit.
    /// @param unitOwner Owner of the unit.
    /// @param unitHash IPFS CID hash of the unit.
    /// @return unitId The id of a minted unit.
    function create(address unitOwner, bytes32 unitHash) external returns (uint256 unitId);
}

/// @title Agent Factory - Periphery smart contract for managing agent and mech creation
contract AgentFactory is GenericManager {
    event CreateMech(address indexed mech, uint256 indexed unitId, uint256 indexed price);

    // Agent factory version number
    string public constant VERSION = "1.0.0";

    // Agent registry address
    address public immutable agentRegistry;

    constructor(address _agentRegistry) {
        agentRegistry = _agentRegistry;
        owner = msg.sender;
    }

    /// @dev Creates agent.
    /// @param unitOwner Owner of the agent.
    /// @param unitHash IPFS hash of the agent.
    /// @param price Minimum required payment the agent accepts.
    /// @return unitId The id of a created agent.
    /// @return mech The created mech instance address.
    function create(
        address unitOwner,
        bytes32 unitHash,
        uint256 price
    ) external returns (uint256 unitId, address mech)
    {
        // Check if the creation is paused
        if (paused) {
            revert Paused();
        }

        unitId = IAgentRegistry(agentRegistry).create(unitOwner, unitHash);
        bytes32 salt = keccak256(abi.encode(unitOwner, unitId));
        // unitOwner is isOperator() for the mech
        mech = address((new AgentMech){salt: salt}(agentRegistry, unitId, price));
        emit CreateMech(mech, unitId, price);
    }
}
