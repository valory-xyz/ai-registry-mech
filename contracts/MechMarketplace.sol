// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrorsMarketplace} from "./interfaces/IErrorsMarketplace.sol";
import {IBalanceTracker} from "./interfaces/IBalanceTracker.sol";
import {IKarma} from "./interfaces/IKarma.sol";
import {IMech} from "./interfaces/IMech.sol";
import {IServiceRegistry} from "./interfaces/IServiceRegistry.sol";

interface IMechFactory {
    /// @dev Registers service as a mech.
    /// @param serviceRegistry Service registry address.
    /// @param serviceId Service id.
    /// @param payload Mech creation payload.
    /// @return mech The created mech instance address.
    function createMech(address serviceRegistry, uint256 serviceId, bytes memory payload)
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
    uint256 responseTimeout;
    // Delivery rate
    uint256 deliveryRate;
}

/// @title Mech Marketplace - Marketplace for posting and delivering requests served by mechs
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Silvere Gangloff - <silvere.gangloff@valory.xyz>
contract MechMarketplace is IErrorsMarketplace {
    event CreateMech(address indexed mech, uint256 indexed serviceId);
    event OwnerUpdated(address indexed owner);
    event ImplementationUpdated(address indexed implementation);
    event MarketplaceParamsUpdated(uint256 fee, uint256 minResponseTimeout, uint256 maxResponseTimeout);
    event SetMechFactoryStatuses(address[] mechFactories, bool[] statuses);
    event SetPaymentTypeBalanceTrackers(bytes32[] paymentTypes, address[] balanceTrackers);
    event MarketplaceRequest(address indexed requester, address indexed requestedMech, uint256 requestId, bytes data);
    event MarketplaceDeliver(address indexed priorityMech, address indexed actualMech, address indexed requester,
        uint256 requestId, bytes data);
    event DeliveryPaymentProcessed(uint256 indexed requestId, address indexed deliveryMech, uint256 deliveryRate, uint256 fee);

    enum RequestStatus {
        DoesNotExist,
        RequestedPriority,
        RequestedExpired,
        Delivered
    }

    // Contract version number
    string public constant VERSION = "1.1.0";
    // Code position in storage is keccak256("MECH_MARKETPLACE_PROXY") = "0xe6194b93a7bff0a54130ed8cd277223408a77f3e48bb5104a9db96d334f962ca"
    bytes32 public constant MECH_MARKETPLACE_PROXY = 0xe6194b93a7bff0a54130ed8cd277223408a77f3e48bb5104a9db96d334f962ca;
    // Domain separator type hash
    bytes32 public constant DOMAIN_SEPARATOR_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    // Fee base constant
    uint256 public constant FEE_BASE = 10_000;

    // Original domain separator value
    bytes32 public immutable domainSeparator;
    // Original chain Id
    uint256 public immutable chainId;
    // Mech karma contract address
    address public immutable karma;
    // Service registry contract address
    address public immutable serviceRegistry;

    // Universal mech marketplace fee (max of 10_000 == 100%)
    uint256 public fee;
    // Minimum response time
    uint256 public minResponseTimeout;
    // Maximum response time
    uint256 public maxResponseTimeout;
    // Number of undelivered requests
    uint256 public numUndeliveredRequests;
    // Number of total requests
    uint256 public numTotalRequests;
    // Number of mechs
    uint256 public numMechs;
    // Reentrancy lock
    uint256 internal _locked = 1;

    // Contract owner
    address public owner;

    // Map of request counts for corresponding requester
    mapping(address => uint256) public mapRequestCounts;
    // Map of delivery counts for corresponding requester
    mapping(address => uint256) public mapDeliveryCounts;
    // Map of delivery counts for mechs
    mapping(address => uint256) public mapMechDeliveryCounts;
    // Map of delivery counts for corresponding mech service multisig
    mapping(address => uint256) public mapMechServiceDeliveryCounts;
    // Mapping of request Id => mech delivery information
    mapping(uint256 => MechDelivery) public mapRequestIdDeliveries;
    // Mapping of whitelisted mech factories
    mapping(address => bool) public mapMechFactories;
    // Map of mech => its creating factory
    mapping(address => address) public mapAgentMechFactories;
    // Map of payment type => balanceTracker address
    mapping(bytes32 => address) public mapPaymentTypeBalanceTrackers;
    // Mapping of account nonces
    mapping(address => uint256) public mapNonces;
    // Mapping of service ids to mechs
    mapping(uint256 => address) public mapServiceIdMech;


    /// @dev MechMarketplace constructor.
    /// @param _serviceRegistry Service registry contract address.
    /// @param _karma Karma proxy contract address.
    constructor(address _serviceRegistry, address _karma) {
        // Check for zero address
        if (_serviceRegistry == address(0) || _karma == address(0)) {
            revert ZeroAddress();
        }

        serviceRegistry = _serviceRegistry;
        karma = _karma;

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

    /// @dev Changes marketplace params.
    /// @param newFee New marketplace fee.
    /// @param newMinResponseTimeout New min response time in sec.
    /// @param newMaxResponseTimeout New max response time in sec.
    function _changeMarketplaceParams(
        uint256 newFee,
        uint256 newMinResponseTimeout,
        uint256 newMaxResponseTimeout
    ) internal {
        // Check for zero values
        if (newFee == 0 || newMinResponseTimeout == 0 || newMaxResponseTimeout == 0) {
            revert ZeroValue();
        }

        // Check for fee value
        if (newFee > FEE_BASE) {
            revert Overflow(newFee, FEE_BASE);
        }

        // Check for sanity values
        if (newMinResponseTimeout > newMaxResponseTimeout) {
            revert Overflow(newMinResponseTimeout, newMaxResponseTimeout);
        }

        // responseTimeout limits
        if (newMaxResponseTimeout > type(uint32).max) {
            revert Overflow(newMaxResponseTimeout, type(uint32).max);
        }

        fee = newFee;
        minResponseTimeout = newMinResponseTimeout;
        maxResponseTimeout = newMaxResponseTimeout;
    }

    /// @dev MechMarketplace initializer.
    /// @param _fee Marketplace fee.
    /// @param _minResponseTimeout Min response time in sec.
    /// @param _maxResponseTimeout Max response time in sec.
    function initialize(uint256 _fee, uint256 _minResponseTimeout, uint256 _maxResponseTimeout) external {
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        _changeMarketplaceParams(_fee, _minResponseTimeout, _maxResponseTimeout);

        owner = msg.sender;
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

    /// @dev Changes the mechMarketplace implementation contract address.
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

        // Store the mechMarketplace implementation address
        // solhint-disable-next-line avoid-low-level-calls
        assembly {
            sstore(MECH_MARKETPLACE_PROXY, newImplementation)
        }

        emit ImplementationUpdated(newImplementation);
    }

    /// @dev Changes marketplace params.
    /// @param newFee New marketplace fee.
    /// @param newMinResponseTimeout New min response time in sec.
    /// @param newMaxResponseTimeout New max response time in sec.
    function changeMarketplaceParams(
        uint256 newFee,
        uint256 newMinResponseTimeout,
        uint256 newMaxResponseTimeout
    ) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        _changeMarketplaceParams(newFee, newMinResponseTimeout, newMaxResponseTimeout);

        emit MarketplaceParamsUpdated(newFee, newMinResponseTimeout, newMaxResponseTimeout);
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

        mech = IMechFactory(mechFactory).createMech(serviceRegistry, serviceId, payload);

        // This should never be the case
        if (mech == address(0)) {
            revert ZeroAddress();
        }

        // Record factory that created a mech
        mapAgentMechFactories[mech] = mechFactory;
        // Add mapping
        mapServiceIdMech[serviceId] = mech;
        numMechs++;

        emit CreateMech(mech, serviceId);
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

    /// @dev Sets mech payment type balanceTrackers.
    /// @param paymentTypes Mech types.
    /// @param balanceTrackers Corresponding balanceTracker addresses.
    function setPaymentTypeBalanceTrackers(bytes32[] memory paymentTypes, address[] memory balanceTrackers) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (paymentTypes.length != balanceTrackers.length) {
            revert WrongArrayLength(paymentTypes.length, balanceTrackers.length);
        }

        // Traverse all the mech types and balanceTrackers
        for (uint256 i = 0; i < paymentTypes.length; ++i) {
            // Check for zero value
            if (paymentTypes[i] == 0) {
                revert ZeroValue();
            }

            // Check for zero address
            if (balanceTrackers[i] == address(0)) {
                revert ZeroAddress();
            }

            mapPaymentTypeBalanceTrackers[paymentTypes[i]] = balanceTrackers[i];
        }

        emit SetPaymentTypeBalanceTrackers(paymentTypes, balanceTrackers);
    }

    /// @dev Registers a request.
    /// @notice The request is going to be registered for a specified priority mech.
    /// @param data Self-descriptive opaque data-blob.
    /// @param priorityMechServiceId Priority mech service Id.
    /// @param requesterServiceId Requester service Id, or zero if EOA.
    /// @param responseTimeout Relative response time in sec.
    /// @param paymentData Additional payment-related request data (optional).
    /// @return requestId Request Id.
    function request(
        bytes memory data,
        uint256 priorityMechServiceId,
        uint256 requesterServiceId,
        uint256 responseTimeout,
        bytes memory paymentData
    ) external payable returns (uint256 requestId) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Response timeout limits
        if (responseTimeout + block.timestamp > type(uint32).max) {
            revert Overflow(responseTimeout + block.timestamp, type(uint32).max);
        }

        // Response timeout bounds
        if (responseTimeout < minResponseTimeout || responseTimeout > maxResponseTimeout) {
            revert OutOfBounds(responseTimeout, minResponseTimeout, maxResponseTimeout);
        }

        // Check for non-zero data
        if (data.length == 0) {
            revert ZeroValue();
        }

        // Check priority mech
        address priorityMech = mapServiceIdMech[priorityMechServiceId];
        if (priorityMech == address(0)) {
            revert ZeroAddress();
        }    

        // Check requester
        checkRequester(msg.sender, requesterServiceId);

        // Get the request Id
        requestId = getRequestId(msg.sender, data, mapNonces[msg.sender]);

        // Get balance tracker address
        bytes32 mechPaymentType = IMech(priorityMech).paymentType();
        address balanceTracker = mapPaymentTypeBalanceTrackers[mechPaymentType];

        // Check and record mech delivery rate
        IBalanceTracker(balanceTracker).checkAndRecordDeliveryRate{value: msg.value}(priorityMech, msg.sender, paymentData);

        // Update requester nonce
        mapNonces[msg.sender]++;

        // Get mech delivery info struct
        MechDelivery storage mechDelivery = mapRequestIdDeliveries[requestId];

        // Record priorityMech and response timeout
        mechDelivery.priorityMech = priorityMech;
        // responseTimeout from relative time to absolute time
        mechDelivery.responseTimeout = responseTimeout + block.timestamp;
        // Record request account
        mechDelivery.requester = msg.sender;
        // Record deliveryRate for request
        mechDelivery.deliveryRate = msg.value;

        // Increase mech requester karma
        IKarma(karma).changeRequesterMechKarma(msg.sender, priorityMech, 1);

        // Record the request count
        mapRequestCounts[msg.sender]++;
        // Increase the number of undelivered requests
        numUndeliveredRequests++;
        // Increase the total number of requests
        numTotalRequests++;

        // Process request by a specified priority mech
        IMech(priorityMech).requestFromMarketplace(msg.sender, data, requestId);

        emit MarketplaceRequest(msg.sender, priorityMech, requestId, data);

        _locked = 1;
    }

    /// @dev Delivers a request.
    /// @notice This function can only be called by the mech delivering the request.
    /// @param requestId Request id.
    /// @param requestData Self-descriptive opaque data-blob.
    function deliverMarketplace(
        uint256 requestId,
        bytes memory requestData
    ) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check delivery mech and get its service multisig
        address mechServiceMultisig = checkMech(msg.sender);

        // Get mech delivery info struct
        MechDelivery storage mechDelivery = mapRequestIdDeliveries[requestId];
        address priorityMech = mechDelivery.priorityMech;

        // Check for request existence
        if (priorityMech == address(0)) {
            revert ZeroAddress();
        }

        // Check if request has been delivered
        if (mechDelivery.deliveryMech != address(0)) {
            revert AlreadyDelivered(requestId);
        }

        // If delivery mech is different from the priority one
        if (priorityMech != msg.sender) {
            // Within the defined response time only a chosen priority mech is able to deliver
            if (block.timestamp > mechDelivery.responseTimeout) {
                // Decrease priority mech karma as the mech did not deliver
                IKarma(karma).changeMechKarma(priorityMech, -1);
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
        mapDeliveryCounts[mechDelivery.requester]++;
        // Increase the amount of mech delivery counts
        mapMechDeliveryCounts[msg.sender]++;
        // Increase the amount of mech service multisig delivered requests
        mapMechServiceDeliveryCounts[mechServiceMultisig]++;

        // Increase mech karma that delivers the request
        IKarma(karma).changeMechKarma(msg.sender, 1);

        // Get balance tracker address
        bytes32 mechPaymentType = IMech(priorityMech).paymentType();
        address balanceTracker = mapPaymentTypeBalanceTrackers[mechPaymentType];

        // Process payment
        IBalanceTracker(balanceTracker).finalizeDeliveryRate(msg.sender, mechDelivery.requester, requestId,
            mechDelivery.deliveryRate);

        emit MarketplaceDeliver(priorityMech, msg.sender, mechDelivery.requester, requestId, requestData);

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
                        address(this),
                        account,
                        data,
                        nonce
                    )
                )
            )
        ));
    }

    /// @dev Checks for mech validity.
    /// @param mech Mech contract address.
    /// @return multisig Mech service multisig address.
    function checkMech(address mech) public view returns (address multisig) {
        uint256 mechServiceId = IMech(mech).tokenId();

        // Check mech validity as it must be created and recorded via this marketplace
        if (mapServiceIdMech[mechServiceId] != mech) {
            revert UnauthorizedAccount(mech);
        }

        // Check mech service Id and get its multisig
        multisig = IMech(mech).getOperator();
    }

    /// @dev Checks for requester validity.
    /// @notice Explicitly allows for EOAs without service id.
    /// @param requester Requester address.
    /// @param requesterServiceId Requester service Id.
    function checkRequester(
        address requester,
        uint256 requesterServiceId
    ) public view {
        // Check for requester service
        if (requesterServiceId > 0) {
            (, address multisig, , , , , IServiceRegistry.ServiceState state) =
                IServiceRegistry(serviceRegistry).mapServices(requesterServiceId);

            // Check for correct service state
            if (state != IServiceRegistry.ServiceState.Deployed) {
                revert WrongServiceState(uint256(state), requesterServiceId);
            }

            // Check staked service multisig
            if (multisig != requester) {
                revert OwnerOnly(requester, multisig);
            }
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
}

