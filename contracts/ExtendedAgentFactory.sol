// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {AgentMech} from "./AgentMech.sol";
import {AgentFactory} from "./AgentFactory.sol";

interface IAgentRegistry {
    /// @dev Checks for the agent existence.
    /// @notice Agent counter starts from 1.
    /// @param agentId Agent Id.
    /// @return true if the agent exists, false otherwise.
    function exists(uint256 agentId) external view returns (bool);
}

/// @dev Agent does not exist.
/// @param agentId Agent Id.
error AgentNotFound(uint256 agentId);

/// @dev Mech already exists.
/// @param mech Mech address.
/// @param agentRegistry Agent Registry address.
/// @param agentId Agent Id.
/// @param price Price value.
error MechAlreadyExist(address mech, address agentRegistry, uint256 agentId, uint256 price);

/// @title Extended Agent Factory - Periphery smart contract for managing agent and mech creation for new and existent agents
contract ExtendedAgentFactory is AgentFactory {
    /// @dev ExtendedAgentFactory constructor.
    /// @param _agentRegistry Agent Registry address.
    /// @param _mechMarketplace Mech Marketplace address.
    constructor(address _agentRegistry, address _mechMarketplace) AgentFactory(_agentRegistry, _mechMarketplace) {}

    /// @dev Adds a mech based on the provided agent Id.
    /// @param registry Agent Registry contract address.
    /// @param agentId The id of an agent.
    /// @param price Minimum required payment the agent accepts.
    /// @return mech The created mech instance address.
    function addMech(address registry, uint256 agentId, uint256 price) external returns (address mech) {
        // Check if the agent exists
        if (!IAgentRegistry(registry).exists(agentId)) {
            revert AgentNotFound(agentId);
        }

        // Create a mech based on the agent Id
        bytes32 salt = keccak256(abi.encode(msg.sender, agentId));

        // Check if the same mech already exists
        bytes memory byteCode = type(AgentMech).creationCode;
        byteCode = abi.encodePacked(byteCode, abi.encode(registry, agentId, price));
        bytes32 hashedAddress = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(byteCode)));
        // Compute the address of the created mech contract
        mech = address(uint160(uint(hashedAddress)));
        if(mech.code.length > 0) {
            revert MechAlreadyExist(mech, registry, agentId, price);
        }

        // Create the mech instance
        (new AgentMech){salt: salt}(registry, agentId, price);
        // ownerOf(uintId) is isOperator() for the mech
        emit CreateMech(mech, agentId, price);
    }
}
