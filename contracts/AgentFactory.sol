// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AgentMech} from "./AgentMech.sol";
import {GenericManager} from "../lib/autonolas-registries/contracts/GenericManager.sol";

interface IAgentRegistry {
    /// @dev Creates a agent.
    /// @param agentOwner Owner of the agent.
    /// @param agentHash IPFS CID hash of the agent metadata.
    /// @return agentId The id of a minted agent.
    function create(address agentOwner, bytes32 agentHash) external returns (uint256 agentId);
}


// Service Registry interface
interface IService {
    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded
    }

    /// @dev Gets the service instance from the map of services.
    /// @param serviceId Service Id.
    /// @return securityDeposit Registration activation deposit.
    /// @return multisig Service multisig address.
    /// @return configHash IPFS hashes pointing to the config metadata.
    /// @return threshold Agent instance signers threshold.
    /// @return maxNumAgentInstances Total number of agent instances.
    /// @return numAgentInstances Actual number of agent instances.
    /// @return state Service state.
    function mapServices(uint256 serviceId) external view returns (uint96 securityDeposit, address multisig,
        bytes32 configHash, uint32 threshold, uint32 maxNumAgentInstances, uint32 numAgentInstances, ServiceState state);
}

/// @title Agent Factory - Periphery smart contract for managing agent and mech creation
contract AgentFactory is GenericManager {
    event CreateMech(address indexed mech, uint256 indexed agentId, uint256 indexed price);

    // Agent factory version number
    string public constant VERSION = "1.1.0";

    // Service registry address
    address public immutable serviceRegistry;

    constructor(address _serviceRegistry) {
        serviceRegistry = _serviceRegistry;
        owner = msg.sender;
    }

    /// @dev Registers service as a mech.
    /// @param serviceId Service id.
    /// @param price Minimum required payment the agent accepts.
    /// @param mechMarketplace Mech marketplace address.
    /// @return mech The created mech instance address.
    function create(
        uint256 serviceId,
        uint256 price,
        address mechMarketplace
    ) external returns (address mech)
    {
        // Check if the creation is paused
        if (paused) {
            revert Paused();
        }
        address multisig;
        (, multisig, , , , , ) = IService(serviceRegistry).mapServices(serviceId);
        // below not needed, checked in OlasMech constructor
        // if (state != IService.ServiceState.Deployed) {
        //     revert WrongServiceState(uint256(state), serviceId);
        // }
        bytes32 salt = keccak256(abi.encode(multisig, serviceId));
        // multisig is isOperator() for the mech
        mech = address((new AgentMech){salt: salt}(serviceRegistry, serviceId, price, mechMarketplace));

        emit CreateMech(mech, serviceId, price);
    }
}
