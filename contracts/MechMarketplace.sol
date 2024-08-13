// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

/// @title ref TODO
/// @dev ref TODO
contract MechMarketplace {
    event Deliver(address indexed sender, uint256 requestId, bytes data);
    event Request(address indexed sender, uint256 requestId, uint256 requestIdWithNonce, bytes data);
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

    // TODO: comments
    address public owner;
    uint256 public minResponceTimeout;
    uint256 public maxResponceTimeout;

    // Minimum required price, ownered???
    uint256 public price;
    // Number of undelivered requests
    uint256 public numUndeliveredRequests;
    // Number of total requests
    uint256 public numTotalRequests;

    // Map of requests counts for corresponding addresses
    mapping(address => uint256) public mapRequestsCounts;
    // Map of undelivered requests counts for corresponding addresses
    mapping(address => uint256) public mapUndeliveredRequestsCounts;
    // Cyclical map of request Ids
    mapping(uint256 => uint256[2]) public mapRequestIds;
    // Map of request Id => sender address
    mapping(uint256 => address) public mapRequestAddresses;
    // Map of account nonces
    mapping(address => uint256) public mapNonces;
    
    // TODO: comments
    mapping(uint256 => uint256) public mapRequestPriority;
    mapping(address => bool) public mapRegisterMech;
    mapping(address => int256) public mapMechKarma;
    address public factory;

    /// @dev MechMarketplace constructor.
    /// @param _price The minimum required price.
    /// @param _minResponceTimeout min timeout in sec
    /// @param _maxResponceTimeout max timeout in sec
    /// @param _factory agentFactory address
    constructor(uint256 _price, uint256 _minResponceTimeout, uint256 _maxResponceTimeout, address _factory) {
        // TODO: comments
        owner = msg.sender;
        minResponceTimeout = _minResponceTimeout;
        maxResponceTimeout = _maxResponceTimeout;
        factory = _factory;

        // Record the price
        price = _price;
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
                keccak256("AgentMech"),
                keccak256(abi.encode(VERSION)),
                block.chainid,
                address(this)
            )
        );
    }

    /// @dev Performs actions before the request is posted.
    /// @param amount Amount of payment in wei.
    function _preRequest(uint256 amount, uint256, bytes memory) internal virtual {
        // Check the request payment
        if (amount < price) {
            revert NotEnoughPaid(amount, price);
        }
    }

    function setRegisterMechStatus(address mech, bool status) external{
        // TODO: rename revert, owner can rewrite mech status/add mech
        if(msg.sender != factory && msg.sender != owner) {
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
        if(priorityMech == address(0)) {
            revert();
        }
        // mech itself can't request
        if(mapRegisterMech[msg.sender]) {
            revert();
        }
        // responseTimeout can't overflow 2^32
        if(responseTimeout < minResponceTimeout || responseTimeout > maxResponceTimeout) {
            revert();
        }
        if(data.length == 0) {
            revert();
        }

        // Get the request Id
        requestId = getRequestId(msg.sender, data);
        requestIdWithNonce = getRequestIdWithNonce(msg.sender, data, mapNonces[msg.sender]);

        // Check the request payment
        _preRequest(msg.value, requestIdWithNonce, data);

        // Increase the requests count supplied by the sender
        mapRequestsCounts[msg.sender]++;
        mapUndeliveredRequestsCounts[msg.sender]++;
        // Record the requestId => sender correspondence
        mapRequestAddresses[requestIdWithNonce] = msg.sender;
        // Update sender's nonce
        mapNonces[msg.sender]++;

        // Record timeout + priorityMech
        uint256 requestPriority = uint160(priorityMech);
        // responseTimeout takes the second 96 bits, from relative time to absolute time
        responseTimeout += block.timestamp;
        requestPriority |= responseTimeout << 160;
        mapRequestPriority[requestIdWithNonce] = requestPriority;

        // Record the request Id in the map
        // Get previous and next request Ids of the first element
        uint256[2] storage requestIds = mapRequestIds[0];
        // Create the new element
        uint256[2] storage newRequestIds = mapRequestIds[requestIdWithNonce];

        // Previous element will be zero, next element will be the current next element
        uint256 curNextRequestId = requestIds[1];
        newRequestIds[1] = curNextRequestId;
        // Next element of the zero element will be the newly created element
        requestIds[1] = requestIdWithNonce;
        // Previous element of the current next element will be the newly created element
        mapRequestIds[curNextRequestId][0] = requestIdWithNonce;

        // Increase the number of undelivered requests
        numUndeliveredRequests++;
        // Increase the total number of requests
        numTotalRequests++;

        emit Request(msg.sender, requestId, requestIdWithNonce, data);
    }

    /// @dev Performs actions before the delivery of a request.
    /// @param data Self-descriptive opaque data-blob.
    /// @return requestData Data for the request processing.
    function _preDeliver(uint256, bytes memory data) internal virtual returns (bytes memory requestData) {
        requestData = data;
    }

    /// @dev Delivers a request.
    /// @param requestId Request id.
    /// @param requestIdWithNonce Request id with nonce.
    /// @param data Self-descriptive opaque data-blob.
    function deliver(uint256 requestId, uint256 requestIdWithNonce, bytes memory data) external {
        // TODO: rename revert
        if(!mapRegisterMech[msg.sender]) {
            revert();
        }
        
        uint256 requestPriority = mapRequestPriority[requestIdWithNonce];
        address expectedMech = address(uint160(requestPriority));
        // TODO: rename revert
        if(expectedMech == address(0)) {
            revert();
        }
        // in windows, TODO: rename revert
        if((requestPriority >> 160) <= block.timestamp) {
            if(expectedMech != msg.sender) {
                revert();
            } 
        } else {
            if(expectedMech != msg.sender) {
                mapMechKarma[expectedMech]--;
            } 
        }
        
        // Perform a pre-delivery of the data if it needs additional parsing
        bytes memory requestData = _preDeliver(requestIdWithNonce, data);

        // Remove delivered request Id from the request Ids map
        uint256[2] memory requestIds = mapRequestIds[requestIdWithNonce];
        // Check if the request Id is invalid (non existent or delivered): previous and next request Ids are zero,
        // and the zero's element previous request Id is not equal to the provided request Id
        if (requestIds[0] == 0 && requestIds[1] == 0 && mapRequestIds[0][0] != requestIdWithNonce) {
            revert RequestIdNotFound(requestIdWithNonce);
        }

        // Re-link previous and next elements between themselves
        mapRequestIds[requestIds[0]][1] = requestIds[1];
        mapRequestIds[requestIds[1]][0] = requestIds[0];

        // Decrease the number of undelivered requests
        numUndeliveredRequests--;
        address account = mapRequestAddresses[requestIdWithNonce];
        mapUndeliveredRequestsCounts[account]--;

        // TODO: comments
        delete mapRequestPriority[requestIdWithNonce];
        mapMechKarma[msg.sender]++;

        // Delete the delivered element from the map
        delete mapRequestIds[requestIdWithNonce];

        emit Deliver(msg.sender, requestId, requestData);
    }

    /// @dev Sets the new price.
    /// @param newPrice New mimimum required price.
    function setPrice(uint256 newPrice) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }
        price = newPrice;
        emit PriceUpdated(newPrice);
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

    /// @dev Gets the requests count for a specific account.
    /// @param account Account address.
    /// @return requestsCount Requests count.
    function getRequestsCount(address account) external view returns (uint256 requestsCount) {
        requestsCount = mapRequestsCounts[account];
    }

    /// @dev Gets the request Id status.
    /// @param requestId Request Id.
    /// @return status Request status.
    function getRequestStatus(uint256 requestId) external view returns (RequestStatus status) {
        // Request exists if it was recorded in the requestId => account map
        if (mapRequestAddresses[requestId] != address(0)) {
            // Get the request info
            uint256[2] memory requestIds = mapRequestIds[requestId];
            // Check if the request Id was already delivered: previous and next request Ids are zero,
            // and the zero's element previous request Id is not equal to the provided request Id
            if (requestIds[0] == 0 && requestIds[1] == 0 && mapRequestIds[0][0] != requestId) {
                status = RequestStatus.Delivered;
            } else {
                status = RequestStatus.Requested;
            }
        }
    }

    /// @dev Gets the set of undelivered request Ids with Nonce.
    /// @param size Maximum batch size of a returned requests Id set. If the size is zero, the whole set is returned.
    /// @param offset The number of skipped requests that are not going to be part of the returned requests Id set.
    /// @return requestIds Set of undelivered request Ids.
    function getUndeliveredRequestIds(uint256 size, uint256 offset) external view returns (uint256[] memory requestIds) {
        // Get the number of undelivered requests
        uint256 numRequests = numUndeliveredRequests;

        // If size is zero, return all the requests
        if (size == 0) {
            size = numRequests;
        }

        // Check for the size + offset overflow
        if (size + offset > numRequests) {
            revert Overflow(size + offset, numRequests);
        }

        if (size > 0) {
            requestIds = new uint256[](size);

            // The first request Id is the next request Id of the zero element in the request Ids map
            uint256 curRequestId = mapRequestIds[0][1];
            // Traverse requests a specified offset
            for (uint256 i = 0; i < offset; ++i) {
                // Next request Id of the current element based on the current request Id
                curRequestId = mapRequestIds[curRequestId][1];
            }

            // Traverse the rest of requests
            for (uint256 i = 0; i < size; ++i) {
                requestIds[i] = curRequestId;
                // Next request Id of the current element based on the current request Id
                curRequestId = mapRequestIds[curRequestId][1];
            }
        }
    }
}

