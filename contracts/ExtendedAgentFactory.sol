// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AgentMech} from "./AgentMech.sol";
import {AgentFactory} from "./AgentFactory.sol";

interface IAgentRegistry {
    /// @dev Checks for the unit existence.
    /// @notice Unit counter starts from 1.
    /// @param unitId Unit Id.
    /// @return true if the unit exists, false otherwise.
    function exists(uint256 unitId) external view returns (bool);
}

/// @dev Unit does not exist.
/// @param unitId Unit Id.
error UnitNotFound(uint256 unitId);

/// @title Extended Agent Factory - Periphery smart contract for managing agent and mech creation for new and existent agents
contract ExtendedAgentFactory is AgentFactory {
    /// @dev ExtendedAgentFactory constructor.
    /// @param _agentRegistry Agent Registry address.
    constructor(address _agentRegistry) AgentFactory(_agentRegistry) {}

    /// @dev Adds a mech based on the provided agent.
    /// @param unitId The id of an agent.
    /// @param price Minimum required payment the agent accepts.
    /// @return mech The created mech instance address.
    function addMech(uint256 unitId, uint256 price) external returns (address mech) {
        // Check if the creation is paused
        if (paused) {
            revert Paused();
        }

        // Check if the agent exists
        if (!IAgentRegistry(agentRegistry).exists(unitId)) {
            revert UnitNotFound(unitId);
        }

        // Create a mech based on the agent Id
        bytes32 salt = keccak256(abi.encode(msg.sender, unitId));
        // ownerOf(uintId) is isOperator() for the mech
        mech = address((new AgentMech){salt: salt}(agentRegistry, unitId, price));
        emit CreateMech(mech, unitId, price);
    }
}
