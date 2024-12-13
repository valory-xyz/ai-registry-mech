// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrorsMarketplace} from "./interfaces/IErrorsMarketplace.sol";
import {IKarma} from "./interfaces/IKarma.sol";
import {IMech} from "./interfaces/IMech.sol";
import {IServiceRegistry} from "./interfaces/IServiceRegistry.sol";
import {IStaking, IStakingFactory} from "./interfaces/IStaking.sol";

interface IMechFactory {
    /// @dev Registers service as a mech.
    /// @param mechMarketplace Mech marketplace address.
    /// @param serviceRegistry Service registry address.
    /// @param serviceId Service id.
    /// @param payload Mech creation payload.
    /// @return mech The created mech instance address.
    function createMech(address mechMarketplace, address serviceRegistry, uint256 serviceId, bytes memory payload)
        external returns (address mech);
}

// Mech delivery info struct
struct MechDelivery {
    // Priority mech address
    address priorityMech;
    // Delivery mech address
    address deliveryMech;
    // Requester address
    address requester;
    // Response timeout window
    uint32 responseTimeout;
}

/// @title Mech Marketplace - Marketplace for posting and delivering requests served by agent mechs
contract MechMarketplace is IErrorsMarketplace {
    event CreateMech(address indexed mech, uint256 indexed serviceId);
    event MarketplaceRequest(address indexed requester, address indexed requestedMech, uint256 requestId, bytes data);
    event MarketplaceDeliver(address indexed priorityMech, address indexed actualMech, address indexed requester,
        uint256 requestId, bytes data);

    enum RequestStatus {
        DoesNotExist,
        RequestedPriority,
        RequestedExpired,
        Delivered
    }

    // Contract version number
    string public constant VERSION = "1.1.0";
    // Domain separator type hash
    bytes32 public constant DOMAIN_SEPARATOR_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    // Original domain separator value
    bytes32 public immutable domainSeparator;
    // Original chain Id
    uint256 public immutable chainId;
    // Minimum response time
    uint256 public immutable minResponseTimeout;
    // Maximum response time
    uint256 public immutable maxResponseTimeout;
    // Mech karma contract address
    address public immutable karmaProxy;
    // Staking factory contract address
    address public immutable stakingFactory;
    // Service registry contract address
    address public immutable serviceRegistry;

    // Number of undelivered requests
    uint256 public numUndeliveredRequests;
    // Number of total requests
    uint256 public numTotalRequests;
    // Reentrancy lock
    uint256 internal _locked = 1;

    // Map of request counts for corresponding requester
    mapping(address => uint256) public mapRequestCounts;
    // Map of delivery counts for corresponding requester
    mapping(address => uint256) public mapDeliveryCounts;
    // Map of delivery counts for corresponding mech service multisig
    mapping(address => uint256) public mapMechServiceDeliveryCounts;
    // Mapping of request Id => mech delivery information
    mapping(uint256 => MechDelivery) public mapRequestIdDeliveries;
    // Mapping of account nonces
    mapping(address => uint256) public mapNonces;

    /// @dev MechMarketplace constructor.
    /// @param _serviceRegistry Service registry contract address.
    /// @param _stakingFactory Staking factory contract address.
    /// @param _karmaProxy Karma proxy contract address.
    /// @param _minResponseTimeout Min response time in sec.
    /// @param _maxResponseTimeout Max response time in sec.
    constructor(
        address _serviceRegistry,
        address _stakingFactory,
        address _karmaProxy,
        uint256 _minResponseTimeout,
        uint256 _maxResponseTimeout
    ) {
        // Check for zero address
        if (_serviceRegistry == address(0) || _stakingFactory == address(0) || _karmaProxy == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero values
        if (_minResponseTimeout == 0 || _maxResponseTimeout == 0) {
            revert ZeroValue();
        }

        // Check for sanity values
        if (_minResponseTimeout > _maxResponseTimeout) {
            revert Overflow(_minResponseTimeout, _maxResponseTimeout);
        }

        // responseTimeout limits
        if (_maxResponseTimeout > type(uint32).max) {
            revert Overflow(_maxResponseTimeout, type(uint32).max);
        }

        serviceRegistry = _serviceRegistry;
        stakingFactory = _stakingFactory;
        karmaProxy = _karmaProxy;
        minResponseTimeout = _minResponseTimeout;
        maxResponseTimeout = _maxResponseTimeout;

        // Record chain Id
        chainId = block.chainid;
        // Compute domain separator
        domainSeparator = _computeDomainSeparator();
    }

    /// @dev Computes domain separator hash.
    /// @return Hash of the domain separator based on its name, version, chain Id and contract address.
    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_SEPARATOR_TYPE_HASH,
                keccak256("MechMarketplace"),
                keccak256(abi.encode(VERSION)),
                block.chainid,
                address(this)
            )
        );
    }

    /// @dev Registers service as a mech.
    /// @param serviceId Service id.
    /// @param mechFactory Mech factory address.
    /// @return mech The created mech instance address.
    function create(uint256 serviceId, address mechFactory, bytes memory payload) external returns (address mech) {
        mech = IMechFactory(mechFactory).createMech(address(this), serviceRegistry, serviceId, payload);

        // This should never be the case
        if (mech == address(0)) {
            revert ZeroAddress();
        }

        emit CreateMech(mech, serviceId);
    }

    /// @dev Registers a request.
    /// @notice The request is going to be registered for a specified priority agent mech.
    /// @param data Self-descriptive opaque data-blob.
    /// @param priorityMech Address of a priority mech.
    /// @param priorityMechStakingInstance Address of a priority mech staking instance (optional).
    /// @param priorityMechServiceId Priority mech service Id.
    /// @param requesterStakingInstance Staking instance of a service whose multisig posts a request (optional).
    /// @param requesterServiceId Corresponding service Id in the staking contract (optional).
    /// @param responseTimeout Relative response time in sec.
    /// @return requestId Request Id.
    function request(
        bytes memory data,
        address priorityMech,
        address priorityMechStakingInstance,
        uint256 priorityMechServiceId,
        address requesterStakingInstance,
        uint256 requesterServiceId,
        uint256 responseTimeout
    ) external payable returns (uint256 requestId) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for zero address
        if (priorityMech == address(0)) {
            revert ZeroAddress();
        }

        // Check that mech staking contract is different from requester one
        if (priorityMechStakingInstance == requesterStakingInstance && priorityMechStakingInstance != address(0)) {
            revert UnauthorizedAccount(priorityMechStakingInstance);
        }

        // Check that msg.sender is not a mech
        if (msg.sender == priorityMech) {
            revert UnauthorizedAccount(msg.sender);
        }

        // responseTimeout bounds
        if (responseTimeout < minResponseTimeout || responseTimeout > maxResponseTimeout) {
            revert OutOfBounds(responseTimeout, minResponseTimeout, maxResponseTimeout);
        }
        // responseTimeout limits
        if (responseTimeout + block.timestamp > type(uint32).max) {
            revert Overflow(responseTimeout + block.timestamp, type(uint32).max);
        }

        // Check for non-zero data
        if (data.length == 0) {
            revert ZeroValue();
        }

        // Check agent mech
        checkMech(priorityMech, priorityMechStakingInstance, priorityMechServiceId);

        // Check requester
        checkRequester(msg.sender, requesterStakingInstance, requesterServiceId);

        // Get the request Id
        requestId = getRequestId(msg.sender, data, mapNonces[msg.sender]);

        // Update sender's nonce
        mapNonces[msg.sender]++;

        // Get mech delivery info struct
        MechDelivery storage mechDelivery = mapRequestIdDeliveries[requestId];

        // Record priorityMech and response timeout
        mechDelivery.priorityMech = priorityMech;
        // responseTimeout from relative time to absolute time
        mechDelivery.responseTimeout = uint32(responseTimeout + block.timestamp);
        // Record request account
        mechDelivery.requester = msg.sender;

        // Increase mech requester karma
        IKarma(karmaProxy).changeRequesterMechKarma(msg.sender, priorityMech, 1);

        // Record the request count
        mapRequestCounts[msg.sender]++;
        // Increase the number of undelivered requests
        numUndeliveredRequests++;
        // Increase the total number of requests
        numTotalRequests++;

        // Process request by a specified priority mech
        IMech(priorityMech).requestFromMarketplace{value: msg.value}(msg.sender, data, requestId);

        emit MarketplaceRequest(msg.sender, priorityMech, requestId, data);

        _locked = 1;
    }

    /// @dev Delivers a request.
    /// @notice This function can only be called by the agent mech delivering the request.
    /// @param requestId Request id.
    /// @param requestData Self-descriptive opaque data-blob.
    /// @param deliveryMechStakingInstance Delivery mech staking instance address (optional).
    /// @param deliveryMechServiceId Mech service Id.
    function deliverMarketplace(
        uint256 requestId,
        bytes memory requestData,
        address deliveryMechStakingInstance,
        uint256 deliveryMechServiceId
    ) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check agent mech and get its mech service multisig
        address mechService = checkMech(msg.sender, deliveryMechStakingInstance, deliveryMechServiceId);

        // Get the staked service info for the mech
        IStaking.ServiceInfo memory serviceInfo =
            IStaking(deliveryMechStakingInstance).getServiceInfo(deliveryMechServiceId);
        // Check that staked service multisig is the priority mech mech service
        if (!IMech(msg.sender).isOperator(serviceInfo.multisig)) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Get mech delivery info struct
        MechDelivery storage mechDelivery = mapRequestIdDeliveries[requestId];
        address priorityMech = mechDelivery.priorityMech;

        // Check for request existence
        if (priorityMech == address(0)) {
            revert ZeroAddress();
        }

        // Check that the delivery mech is not a requester
        address requester = mechDelivery.requester;
        if (msg.sender == requester) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Check that the request is not already delivered
        if (mechDelivery.deliveryMech != address(0)) {
            revert AlreadyDelivered(requestId);
        }

        // If delivery mech is different from the priority one
        if (priorityMech != msg.sender) {
            // Within the defined response time only a chosen priority mech is able to deliver
            if (block.timestamp > mechDelivery.responseTimeout) {
                // Decrease priority mech karma as the mech did not deliver
                IKarma(karmaProxy).changeMechKarma(priorityMech, -1);
                // Revoke request from the priority mech
                IMech(priorityMech).revokeRequest(requestId);
            } else {
                // Priority mech responseTimeout is still >= block.timestamp
                revert PriorityMechResponseTimeout(mechDelivery.responseTimeout, block.timestamp);
            }
        }

        // Record the actual delivery mech
        mechDelivery.deliveryMech = msg.sender;

        // Decrease the number of undelivered requests
        numUndeliveredRequests--;
        // Increase the amount of requester delivered requests
        mapDeliveryCounts[requester]++;
        // Increase the amount of mech service multisig delivered requests
        mapMechServiceDeliveryCounts[mechService]++;

        // Increase mech karma that delivers the request
        IKarma(karmaProxy).changeMechKarma(msg.sender, 1);

        emit MarketplaceDeliver(priorityMech, msg.sender, requester, requestId, requestData);

        _locked = 1;
    }

    /// @dev Gets the already computed domain separator of recomputes one if the chain Id is different.
    /// @return Original or recomputed domain separator.
    function getDomainSeparator() public view returns (bytes32) {
        return block.chainid == chainId ? domainSeparator : _computeDomainSeparator();
    }

    /// @dev Gets the request Id.
    /// @param account Account address.
    /// @param data Self-descriptive opaque data-blob.
    /// @param nonce Nonce.
    /// @return requestId Corresponding request Id.
    function getRequestId(
        address account,
        bytes memory data,
        uint256 nonce
    ) public view returns (uint256 requestId) {
        requestId = uint256(keccak256(
            abi.encodePacked(
                "\x19\x01",
                getDomainSeparator(),
                keccak256(
                    abi.encode(
                        account,
                        data,
                        nonce
                    )
                )
            )
        ));
    }

    /// @dev Checks for service validity and optionally for service staking correctness.
    /// @param stakingInstance Staking instance address.
    /// @param serviceId Service Id.
    /// @return multisig Service multisig address.
    function checkServiceAndGetMultisig(
        address stakingInstance,
        uint256 serviceId
    ) public view returns (address multisig) {
        // Check mech service Id
        if (stakingInstance == address(0)) {
            IServiceRegistry.ServiceState state;
            (, multisig, , , , , state) = IServiceRegistry(serviceRegistry).mapServices(serviceId);
            if (state != IServiceRegistry.ServiceState.Deployed) {
                revert WrongServiceState(uint256(state), serviceId);
            }
        } else {
            // Check staking instance
            checkStakingInstance(stakingInstance, serviceId);

            // Get the staked service info for the mech
            IStaking.ServiceInfo memory serviceInfo = IStaking(stakingInstance).getServiceInfo(serviceId);
            multisig = serviceInfo.multisig;
        }
    }

    /// @dev Checks for staking instance contract validity.
    /// @param stakingInstance Staking instance address.
    /// @param serviceId Service Id.
    function checkStakingInstance(address stakingInstance, uint256 serviceId) public view {
        // Check that the mech staking instance is valid
        if (!IStakingFactory(stakingFactory).verifyInstance(stakingInstance)) {
            revert UnauthorizedAccount(stakingInstance);
        }

        // Check if the mech service is staked
        IStaking.StakingState state = IStaking(stakingInstance).getStakingState(serviceId);
        if (state != IStaking.StakingState.Staked) {
            revert ServiceNotStaked(stakingInstance, serviceId);
        }
    }

    /// @dev Checks for mech validity.
    /// @dev mech Agent mech contract address.
    /// @param mechStakingInstance Agent mech staking instance address.
    /// @param mechServiceId Agent mech service Id.
    /// @return multisig Service multisig address.
    function checkMech(
        address mech,
        address mechStakingInstance,
        uint256 mechServiceId
    ) public view returns (address multisig) {
        // Check for zero value
        if (mechServiceId == 0) {
            revert ZeroValue();
        }

        // Check marketplace address
        address checkMarketplace = IMech(mech).mechMarketplace();
        if (checkMarketplace != address(this)) {
            revert UnauthorizedAccount(checkMarketplace);
        }

        // Check mech service Id and staking instance, if applicable
        multisig = checkServiceAndGetMultisig(mechStakingInstance, mechServiceId);

        // Check that service multisig is the priority mech service multisig
        if (!IMech(mech).isOperator(multisig)) {
            revert UnauthorizedAccount(mech);
        }
    }

    /// @dev Checks for requester validity.
    /// @dev requester Requester contract address.
    /// @param requesterStakingInstance Requester staking instance address.
    /// @param requesterServiceId Requester service Id.
    function checkRequester(
        address requester,
        address requesterStakingInstance,
        uint256 requesterServiceId
    ) public view {
        // Check for requester service
        if (requesterServiceId > 0) {
            address multisig = checkServiceAndGetMultisig(requesterStakingInstance, requesterServiceId);

            // Check staked service multisig
            if (multisig != requester) {
                revert OwnerOnly(requester, multisig);
            }
        } else if (requesterStakingInstance != address(0)) {
            // Check for inconsistency between zero service Id and non-zero staking instance
            revert ZeroValue();
        }
    }

    /// @dev Gets the request Id status.
    /// @param requestId Request Id.
    /// @return status Request status.
    function getRequestStatus(uint256 requestId) external view returns (RequestStatus status) {
        // Request exists if it has a record in the mapRequestIdDeliveries
        MechDelivery memory mechDelivery = mapRequestIdDeliveries[requestId];
        if (mechDelivery.priorityMech != address(0)) {
            // Check if the request Id was already delivered: delivery mech address is not zero
            if (mechDelivery.deliveryMech == address(0)) {
                if (block.timestamp > mechDelivery.responseTimeout) {
                    status = RequestStatus.RequestedExpired;
                } else {
                    status = RequestStatus.RequestedPriority;
                }
            } else {
                status = RequestStatus.Delivered;
            }
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

    /// @dev Gets deliveries count for a specific mech service multisig.
    /// @param mechService Agent mech service multisig address.
    /// @return Deliveries count.
    function getMechServiceDeliveriesCount(address mechService) external view returns (uint256) {
        return mapMechServiceDeliveryCounts[mechService];
    }

    /// @dev Gets mech delivery info.
    /// @param requestId Request Id.
    /// @return Mech delivery info.
    function getMechDeliveryInfo(uint256 requestId) external view returns (MechDelivery memory) {
        return mapRequestIdDeliveries[requestId];
    }
}

