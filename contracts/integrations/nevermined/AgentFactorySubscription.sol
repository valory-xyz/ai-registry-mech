// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AgentMechSubscription} from "./AgentMechSubscription.sol";
import {GenericManager} from "../../../lib/autonolas-registries/contracts/GenericManager.sol";

interface IAgentRegistry {
    /// @dev Creates a agent.
    /// @param agentOwner Owner of the agent.
    /// @param agentHash IPFS CID hash of the agent metadata.
    /// @return agentId The id of a minted agent.
    function create(address agentOwner, bytes32 agentHash) external returns (uint256 agentId);
}

// Mech Marketplace interface
interface IMechMarketplace {
    /// @dev Sets mech registration status.
    /// @param mech Mech address.
    /// @param status True, if registered, false otherwise.
    function setMechRegistrationStatus(address mech, bool status) external;
}

/// @title Agent Factory Subscription - Periphery smart contract for managing agent and mech creation with subscription
contract AgentFactorySubscription is GenericManager {
    event CreateMech(
        address indexed mech,
        uint256 indexed agentId,
        uint256 minCreditsPerRequest,
        address indexed subscriptionNFT,
        uint256 subscriptionTokenId
    );

    // Agent factory version number
    string public constant VERSION = "1.1.0";

    // Agent registry address
    address public immutable agentRegistry;

    constructor(address _agentRegistry) {
        agentRegistry = _agentRegistry;
        owner = msg.sender;
    }

    /// @dev Creates agent.
    /// @param agentOwner Owner of the agent.
    /// @param agentHash IPFS CID hash of the agent metadata.
    /// @param minCreditsPerRequest Minimum number of credits to pay for each request via a subscription.
    /// @param subscriptionNFT Subscription address.
    /// @param subscriptionTokenId Subscription token Id.
    /// @param mechMarketplace Mech marketplace address.
    /// @return agentId The id of a created agent.
    /// @return mech The created mech instance address.
    function create(
        address agentOwner,
        bytes32 agentHash,
        uint256 minCreditsPerRequest,
        address subscriptionNFT,
        uint256 subscriptionTokenId,
        address mechMarketplace
    ) external returns (uint256 agentId, address mech)
    {
        // Check if the creation is paused
        if (paused) {
            revert Paused();
        }

        agentId = IAgentRegistry(agentRegistry).create(agentOwner, agentHash);
        bytes32 salt = keccak256(abi.encode(agentOwner, agentId));
        // agentOwner is isOperator() for the mech
        mech = address((new AgentMechSubscription){salt: salt}(agentRegistry, agentId,
            minCreditsPerRequest, subscriptionNFT, subscriptionTokenId, mechMarketplace));

        // Register mech in a marketplace, if specified
        if (mechMarketplace != address(0)) {
            IMechMarketplace(mechMarketplace).setMechRegistrationStatus(mech, true);
        }

        emit CreateMech(mech, agentId, minCreditsPerRequest, subscriptionNFT, subscriptionTokenId);
    }
}
