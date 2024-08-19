// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Agent Mech interface
interface IMech {
    function request(address account, bytes memory data, uint256 requestId, uint256 requestIdWithNonce) external payable;
    function revokeRequest(uint256 requestIdWithNonce) external;
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Agent does not exist.
/// @param agentId Agent Id.
error AgentNotFound(uint256 agentId);

/// @dev Not enough value paid.
/// @param provided Provided amount.
/// @param expected Expected amount.
error NotEnoughPaid(uint256 provided, uint256 expected);

/// @dev Request Id not found.
/// @param requestId Request Id.
error RequestIdNotFound(uint256 requestId);

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

struct MechDelivery {
    address priorityMech;
    address deliveryMech;
    address account;
    uint32 responseTimeout;
}

/// @title ref TODO
/// @dev ref TODO
contract MechMarketplace {
    event MarketplaceDeliver(address indexed priorityMech, address indexed actualMech, address indexed requester,
        uint256 requestId, bytes data);
    event MarketplaceRequest(address indexed requester, address indexed requestedMech, uint256 requestId,
        uint256 requestIdWithNonce, bytes data);
    event PriceUpdated(uint256 price);

    enum RequestStatus {
        DoesNotExist,
        Requested,
        Delivered
    }

    // version number
    string public constant VERSION = "1.0.0";
    // Domain separator type hash
    bytes32 public constant DOMAIN_SEPARATOR_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    // Original domain separator value
    bytes32 public immutable domainSeparator;
    // Original chain Id
    uint256 public immutable chainId;

    // Number of undelivered requests
    uint256 public numUndeliveredRequests;
    // Number of total requests
    uint256 public numTotalRequests;
    // TODO: comments
    uint256 public minResponseTimeout;
    uint256 public maxResponseTimeout;
    address public owner;
    // Mech factory contract address
    address public factory;
    
    // Map of request Id => mech delivery information
    mapping(uint256 => MechDelivery) public mapRequestIdDeliveries;
    // Map of account nonces
    mapping(address => uint256) public mapNonces;
    
    // TODO: comments
    mapping(address => bool) public mapRegisterMech;
    mapping(address => int256) public mapMechKarma;
    mapping(address => mapping(address => uint256)) public mapRequesterMechKarma;

    /// @dev MechMarketplace constructor.
    /// @param _minResponceTimeout min timeout in sec
    /// @param _maxResponceTimeout max timeout in sec
    /// @param _factory agentFactory address
    constructor(uint256 _minResponceTimeout, uint256 _maxResponceTimeout, address _factory) {
        // TODO: comments
        owner = msg.sender;
        minResponseTimeout = _minResponceTimeout;
        maxResponseTimeout = _maxResponceTimeout;
        factory = _factory;

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

    function changeFactory(address newFactory) external {
        if (msg.sender != owner) {
            revert();
        }

        if (newFactory == address(0)) {
            revert ZeroAddress();
        }

        factory = newFactory;
        // TODO event
    }

    function setRegisterMechStatus(address mech, bool status) external{
        // TODO: rename revert, owner can rewrite mech status/add mech
        if (msg.sender != factory && msg.sender != owner) {
            revert();
        }

        // Check that mech is a contract
        if (mech.code.length == 0) {
            revert();
        }

        mapRegisterMech[mech] = status;
        // TODO: event
    }

    /// @dev Registers a request.
    /// @param data Self-descriptive opaque data-blob.
    /// @param priorityMech address of priority mech
    /// @param responseTimeout relative timeout in sec
    function request(bytes memory data, address priorityMech, uint256 responseTimeout) external payable returns (uint256 requestId, uint256 requestIdWithNonce) {
        // TODO: rename revert
        if (priorityMech == address(0)) {
            revert();
        }
        // mech itself can't request
        if (mapRegisterMech[msg.sender]) {
            revert();
        }
        // Check that priority mech is registered
        if (!mapRegisterMech[priorityMech]) {
            revert();
        }
        // responseTimeout can't overflow 2^32
        if (responseTimeout < minResponseTimeout || responseTimeout > maxResponseTimeout) {
            revert();
        }
        if (data.length == 0) {
            revert();
        }

        // Get the request Id
        requestId = getRequestId(msg.sender, data);
        requestIdWithNonce = getRequestIdWithNonce(msg.sender, data, mapNonces[msg.sender]);

        // Update sender's nonce
        mapNonces[msg.sender]++;

        MechDelivery storage mechDelivery = mapRequestIdDeliveries[requestIdWithNonce];

        // Record timeout + priorityMech
        mechDelivery.priorityMech = priorityMech;
        // responseTimeout from relative time to absolute time
        mechDelivery.responseTimeout = uint32(responseTimeout + block.timestamp);
        // Record request account
        mechDelivery.account = msg.sender;

        // Increase mech requester karma
        mapRequesterMechKarma[msg.sender][priorityMech]++;

        // Increase the number of undelivered requests
        numUndeliveredRequests++;
        // Increase the total number of requests
        numTotalRequests++;

        IMech(priorityMech).request{value: msg.value}(msg.sender, data, requestId, requestIdWithNonce);

        emit MarketplaceRequest(msg.sender, priorityMech, requestId, requestIdWithNonce, data);
    }

    /// @dev Delivers a request.
    /// @param requestId Request id.
    /// @param requestIdWithNonce Request id with nonce.
    /// @param requestData Self-descriptive opaque data-blob.
    function deliver(uint256 requestId, uint256 requestIdWithNonce, bytes memory requestData) external {
        // TODO: rename revert
        if (!mapRegisterMech[msg.sender]) {
            revert();
        }

        MechDelivery storage mechDelivery = mapRequestIdDeliveries[requestIdWithNonce];
        address priorityMech = mechDelivery.priorityMech;
        // TODO: rename revert - no request to deliver
        if (priorityMech == address(0)) {
            revert();
        }

        address account = mechDelivery.account;

        // Already delivered
        if (mechDelivery.deliveryMech != address(0)) {
            revert();
        }
        // in windows, TODO: rename revert
        if (mechDelivery.responseTimeout <= block.timestamp) {
            if (priorityMech != msg.sender) {
                revert();
            }
        } else {
            if (priorityMech != msg.sender) {
                mapMechKarma[priorityMech]--;
                IMech(priorityMech).revokeRequest(requestIdWithNonce);
            } 
        }

        mechDelivery.deliveryMech = msg.sender;

        // Decrease the number of undelivered requests
        numUndeliveredRequests--;

        // TODO: comments
        mapMechKarma[msg.sender]++;

        emit MarketplaceDeliver(priorityMech, msg.sender, account, requestId, requestData);
    }

    /// @dev Gets the already computed domain separator of recomputes one if the chain Id is different.
    /// @return Original or recomputed domain separator.
    function getDomainSeparator() public view returns (bytes32) {
        return block.chainid == chainId ? domainSeparator : _computeDomainSeparator();
    }

    /// @dev Gets the request Id.
    /// @param account Account address.
    /// @param data Self-descriptive opaque data-blob.
    /// @return requestId Corresponding request Id.
    function getRequestId(address account, bytes memory data) public pure returns (uint256 requestId) {
        requestId = uint256(keccak256(abi.encode(account, data)));
    }

    /// @dev Gets the request Id with a specific nonce.
    /// @param account Account address.
    /// @param data Self-descriptive opaque data-blob.
    /// @param nonce Nonce.
    /// @return requestId Corresponding request Id.
    function getRequestIdWithNonce(
        address account,
        bytes memory data,
        uint256 nonce
    ) public view returns (uint256 requestId)
    {
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

    /// @dev Gets the request Id status.
    /// @param requestIdWithNonce Request Id with nonce.
    /// @return status Request status.
    function getRequestStatus(uint256 requestIdWithNonce) external view returns (RequestStatus status) {
        // Request exists if it has a record in the mapRequestIdDeliveries
        MechDelivery memory mechDelivery = mapRequestIdDeliveries[requestIdWithNonce];
        if (mechDelivery.priorityMech != address(0)) {
            // Check if the request Id was already delivered: delivery mech address is not zero
            if (mechDelivery.deliveryMech == address(0)) {
                status = RequestStatus.Requested;
            } else {
                status = RequestStatus.Delivered;
            }
        }
    }

    function getMechDeliveryInfo(uint256 requestIdWithNonce) external view returns (MechDelivery memory) {
        return mapRequestIdDeliveries[requestIdWithNonce];
    }
}

