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

/// @dev Mech already exists.
/// @param mech Mech address.
/// @param agentRegistry Agent Registry address.
/// @param unitId Unit Id.
/// @param price Price value.
error MechAlreadyExist(address mech, address agentRegistry, uint256 unitId, uint256 price);

/// @title Extended Agent Factory - Periphery smart contract for managing agent and mech creation for new and existent agents
contract ExtendedAgentFactory is AgentFactory {
    /// @dev ExtendedAgentFactory constructor.
    /// @param _agentRegistry Agent Registry address.
    constructor(address _agentRegistry) AgentFactory(_agentRegistry) {}

    /// @dev Adds a mech based on the provided unit Id.
    /// @param registry Unit Registry contract address.
    /// @param unitId The id of an agent.
    /// @param price Minimum required payment the agent accepts.
    /// @return mech The created mech instance address.
    function addMech(address registry, uint256 unitId, uint256 price) external returns (address mech) {
        // Check if the agent exists
        if (!IAgentRegistry(registry).exists(unitId)) {
            revert UnitNotFound(unitId);
        }

        // Create a mech based on the agent Id
        bytes32 salt = keccak256(abi.encode(msg.sender, unitId));

        // Check if the same mech already exists
        bytes memory byteCode = type(AgentMech).creationCode;
        byteCode = abi.encodePacked(byteCode, abi.encode(registry, unitId, price));
        bytes32 hashedAddress = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(byteCode)));
        // Compute the address of the created mech contract
        mech = address(uint160(uint(hashedAddress)));
        if(mech.code.length > 0) {
            revert MechAlreadyExist(mech, registry, unitId, price);
        }

        // Create the mech instance
        (new AgentMech){salt: salt}(registry, unitId, price);
        // ownerOf(uintId) is isOperator() for the mech
        emit CreateMech(mech, unitId, price);
    }
}
