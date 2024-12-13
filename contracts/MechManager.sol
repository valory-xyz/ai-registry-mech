// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMechFactory {
    /// @dev Registers service as a mech.
    /// @param mechManager Mech manager address.
    /// @param serviceRegistry Service registry address.
    /// @param serviceId Service id.
    /// @param payload Mech creation payload.
    /// @return mech The created mech instance address.
    function createMech(address mechManager, address serviceRegistry, uint256 serviceId, bytes memory payload)
        external returns (address mech);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Account is unauthorized.
/// @param account Account address.
error UnauthorizedAccount(address account);

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

/// @title MechManager - Smart contract for mech manager
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract MechManager {
    event CreateMech(address indexed mech, uint256 indexed serviceId);
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event SetMechMarketplaceStatuses(address[] mechMarketplaces, bool[] statuses);
    event SetMechFactoryStatuses(address[] mechFactories, bool[] statuses);

    // Version number
    string public constant VERSION = "1.0.0";
    // Code position in storage is keccak256("MECH_MANAGER_PROXY") = "0x4d988168e3618e8ed79943415869916bdedf776fc6197c43f9336905a622dab2"
    bytes32 public constant MECH_MANAGER_PROXY = 0x4d988168e3618e8ed79943415869916bdedf776fc6197c43f9336905a622dab2;

    // Service registry contract address
    address public immutable serviceRegistry;

    // Universal mech marketplace fee
    uint256 fee;
    // Number of undelivered requests
    uint256 public numUndeliveredRequests;
    // Number of total requests
    uint256 public numTotalRequests;

    // Contract owner
    address public owner;

    // Mapping of whitelisted mech marketplaces
    mapping(address => bool) public mapMechMarketplaces;
    // Mapping of whitelisted mech factories
    mapping(address => bool) public mapMechFactories;
    // Map of request counts for corresponding requester
    mapping(address => uint256) public mapRequestCounts;
    // Map of delivery counts for corresponding requester
    mapping(address => uint256) public mapDeliveryCounts;
    // Map of delivery counts for agent mech
    mapping(address => uint256) public mapAgentMechDeliveryCounts;
    // Map of delivery counts for corresponding mech service multisig
    mapping(address => uint256) public mapMechServiceDeliveryCounts;
    // Map of agent mech => its creating factory
    mapping(address => address) public mapAgentMechFactories;

    /// @dev MechManager implementation constructor.
    /// @param _serviceRegistry Service registry address.
    constructor(address _serviceRegistry) {
        serviceRegistry = _serviceRegistry;
    }

    /// @dev MechManager initializer.
    function initialize(uint256 _fee) external{
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
        fee = _fee;
    }

    /// @dev Changes the mechManager implementation contract address.
    /// @param newImplementation New implementation contract address.
    function changeImplementation(address newImplementation) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newImplementation == address(0)) {
            revert ZeroAddress();
        }

        // Store the mechManager implementation address
        assembly {
            sstore(MECH_MANAGER_PROXY, newImplementation)
        }

        emit ImplementationUpdated(newImplementation);
    }

    /// @dev Changes contract owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Registers service as a mech.
    /// @param serviceId Service id.
    /// @param mechFactory Mech factory address.
    /// @return mech The created mech instance address.
    function create(uint256 serviceId, address mechFactory, bytes memory payload) external returns (address mech) {
        // Check for factory status
        if (!mapMechFactories[mechFactory]) {
            revert UnauthorizedAccount(mechFactory);
        }

        mech = IMechFactory(mechFactory).createMech(address(this), serviceRegistry, serviceId, payload);

        // This should never be the case
        if (mech == address(0)) {
            revert ZeroAddress();
        }

        // Record factory that created agent mech
        mapAgentMechFactories[mech] = mechFactory;

        emit CreateMech(mech, serviceId);
    }

    /// @dev Sets mech marketplace statues.
    /// @param mechMarketplaces Mech marketplace contract addresses.
    /// @param statuses Corresponding whitelisting statues.
    function setMechMarketplaceStatuses(address[] memory mechMarketplaces, bool[] memory statuses) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (mechMarketplaces.length != statuses.length) {
            revert WrongArrayLength(mechMarketplaces.length, statuses.length);
        }

        // Traverse all the mech marketplaces and statuses
        for (uint256 i = 0; i < mechMarketplaces.length; ++i) {
            if (mechMarketplaces[i] == address(0)) {
                revert ZeroAddress();
            }

            mapMechMarketplaces[mechMarketplaces[i]] = statuses[i];
        }

        emit SetMechMarketplaceStatuses(mechMarketplaces, statuses);
    }

    /// @dev Sets mech factory statues.
    /// @param mechFactories Mech marketplace contract addresses.
    /// @param statuses Corresponding whitelisting statues.
    function setMechFactoryStatuses(address[] memory mechFactories, bool[] memory statuses) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (mechFactories.length != statuses.length) {
            revert WrongArrayLength(mechFactories.length, statuses.length);
        }

        // Traverse all the mech marketplaces and statuses
        for (uint256 i = 0; i < mechFactories.length; ++i) {
            if (mechFactories[i] == address(0)) {
                revert ZeroAddress();
            }

            mapMechFactories[mechFactories[i]] = statuses[i];
        }

        emit SetMechFactoryStatuses(mechFactories, statuses);
    }

    function increaseRequestsCounts(address requester) external {
        // Check for marketplace access
        if (!mapMechMarketplaces[msg.sender]) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Record the request count
        mapRequestCounts[requester]++;
        // Increase the number of undelivered requests
        numUndeliveredRequests++;
        // Increase the total number of requests
        numTotalRequests++;
    }

    function increaseDeliveryCounts(address requester, address agentMech, address mechServiceMultisig) external {
        // Check for marketplace access
        if (!mapMechMarketplaces[msg.sender]) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Decrease the number of undelivered requests
        numUndeliveredRequests--;
        // Increase the amount of requester delivered requests
        mapDeliveryCounts[requester]++;
        // Increase the amount of agent mech delivery counts
        mapAgentMechDeliveryCounts[agentMech]++;
        // Increase the amount of mech service multisig delivered requests
        mapMechServiceDeliveryCounts[mechServiceMultisig]++;
    }

    /// @dev Validates agent mech.
    /// @param agentMech Agent mech address.
    /// @return status True, if the mech is valid.
    function checkMechValidity(address agentMech) external view returns (bool status) {
        // TODO: shall we also check the status of the factory?
        // TODO: if yes, what if the factory was de-whitelisted? all the mechs then become invalid
        status = mapAgentMechFactories[agentMech] != address(0);
    }

    /// @dev Gets the implementation address.
    /// @return implementation Implementation address.
    function getImplementation() external view returns (address implementation) {
        assembly {
            implementation := sload(MECH_MANAGER_PROXY)
        }
    }

    /// @dev Gets the requests count for a specific account.
    /// @param account Account address.
    /// @return Requests count.
    function getRequestsCount(address account) external view returns (uint256) {
        return mapRequestCounts[account];
    }

    /// @dev Gets the deliveries count for a specific account.
    /// @param account Account address.
    /// @return Deliveries count.
    function getDeliveriesCount(address account) external view returns (uint256) {
        return mapDeliveryCounts[account];
    }

    /// @dev Gets deliveries count for a specific agent mech.
    /// @param agentMech Agent mech address.
    /// @return Deliveries count.
    function getAgentMechDeliveriesCount(address agentMech) external view returns (uint256) {
        return mapAgentMechDeliveryCounts[agentMech];
    }

    /// @dev Gets deliveries count for a specific mech service multisig.
    /// @param mechServiceMultisig Agent mech service multisig address.
    /// @return Deliveries count.
    function getMechServiceDeliveriesCount(address mechServiceMultisig) external view returns (uint256) {
        return mapMechServiceDeliveryCounts[mechServiceMultisig];
    }
}