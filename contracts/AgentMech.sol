// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC721Mech} from "../lib/gnosis-mech/contracts/ERC721Mech.sol";

interface IToken {
    /// @dev Gets the owner of the `tokenId` token.
    /// @param tokenId Token Id that must exist.
    /// @return tokenOwner Token owner.
    function ownerOf(uint256 tokenId) external view returns (address tokenOwner);
}

interface IMechMarketplace {
    /// @dev Delivers a request.
    /// @param requestId Request id.
    /// @param requestIdWithNonce Request id with nonce.
    /// @param requestData Self-descriptive opaque data-blob.
    function deliver(uint256 requestId, uint256 requestIdWithNonce, bytes memory requestData) external;
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

/// @title AgentMech - Smart contract for extending ERC721Mech
/// @dev A Mech that is operated by the holder of an ERC721 non-fungible token.
contract AgentMech is ERC721Mech {
    event Deliver(address indexed sender, uint256 requestId, uint256 requestIdWithNonce, bytes data);
    event Request(address indexed sender, uint256 requestId, uint256 requestIdWithNonce, bytes data);
    event PriceUpdated(uint256 price);

    enum RequestStatus {
        DoesNotExist,
        Requested,
        Delivered
    }

    // Agent mech version number
    string public constant VERSION = "1.1.0";

    // Minimum required price
    uint256 public price;
    // Number of undelivered requests
    uint256 public numUndeliveredRequests;
    // Number of total requests
    uint256 public numTotalRequests;
    // Mech marketplace address
    address public mechMarketplace;

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

    /// @dev AgentMech constructor.
    /// @param _token Address of the token contract.
    /// @param _tokenId The token ID.
    /// @param _price The minimum required price.
    constructor(address _mechMarketplace, address _token, uint256 _tokenId, uint256 _price) ERC721Mech(_token, _tokenId) {
        // Check for zero addresses
        if (_mechMarketplace == address(0) || _token == address(0)) {
            revert ZeroAddress();
        }

        // Check for the token to have the owner
        address tokenOwner = IToken(_token).ownerOf(_tokenId);
        if (tokenOwner == address(0)) {
            revert AgentNotFound(_tokenId);
        }

        // Record the mech marketplace
        mechMarketplace = _mechMarketplace;
        // Record the price
        price = _price;
    }

    /// @dev Changes mech marketplace address.
    /// @param newMechMarketplace New mech marketplace address.
    function changeMechMarketplace(address newMechMarketplace) external onlyOperator {
        // Check for zero address
        if (newMechMarketplace == address(0)) {
            revert ZeroAddress();
        }

        mechMarketplace = newMechMarketplace;
    }

    /// @dev Performs actions before the request is posted.
    /// @param amount Amount of payment in wei.
    function _preRequest(uint256 amount, uint256, bytes memory) internal virtual {
        // Check the request payment
        if (amount < price) {
            revert NotEnoughPaid(amount, price);
        }
    }

    /// @dev Registers a request.
    /// @param data Self-descriptive opaque data-blob.
    function request(address account, bytes memory data, uint256 requestId, uint256 requestIdWithNonce) external payable {
        if (msg.sender != mechMarketplace) {
            revert();
        }

        // Check the request payment
        _preRequest(msg.value, requestIdWithNonce, data);

        // Increase the requests count supplied by the sender
        mapRequestsCounts[account]++;
        mapUndeliveredRequestsCounts[account]++;
        // Record the requestId => sender correspondence
        mapRequestAddresses[requestIdWithNonce] = account;

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

        emit Request(account, requestId, requestIdWithNonce, data);
    }

    function recordRequest(address account, uint256 requestId, uint256 requestIdWithNonce) external {
        if (msg.sender != mechMarketplace) {
            revert();
        }

        // Increase the number of undelivered and total number of requests
        mapRequestsCounts[account]++;
        numTotalRequests++;

        // TODO Event
    }

    function revokeRequest(uint256 requestId, uint256 requestIdWithNonce) external {
        if (msg.sender != mechMarketplace) {
            revert();
        }

        address account = mapRequestAddresses[requestIdWithNonce];
        // This must never happen
        if (account == address(0)) {
            revert();
        }
        // Decrease the number of undelivered and total number of requests
        mapUndeliveredRequestsCounts[account]--;
        mapRequestsCounts[account]--;
        numUndeliveredRequests--;
        numTotalRequests--;

        // Delete revoked request from maps
        delete mapRequestIds[requestIdWithNonce];
        delete mapRequestAddresses[requestIdWithNonce];

        // TODO Event
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
    function deliver(uint256 requestId, uint256 requestIdWithNonce, bytes memory data) external onlyOperator {
        // Perform a pre-delivery of the data if it needs additional parsing
        bytes memory requestData = _preDeliver(requestIdWithNonce, data);

        // Get the account to deliver request to
        address account = mapRequestAddresses[requestIdWithNonce];
        // The account is non-zero if it is delivered by the priority mech, otherwise it is being delivered by another one
        // All the statistics then is going to be managed in that another delivery mech
        if (account != address(0)) {
            // Decrease the number of undelivered requests
            mapUndeliveredRequestsCounts[account]--;
            numUndeliveredRequests--;

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

            // Delete the delivered element from the map
            delete mapRequestIds[requestIdWithNonce];
            delete mapRequestAddresses[requestIdWithNonce];
        }

        // Mech marketplace delivery finalization
        IMechMarketplace(mechMarketplace).deliver(requestId, requestIdWithNonce, requestData);

        emit Deliver(msg.sender, requestId, requestIdWithNonce, requestData);
    }

    /// @dev Sets the new price.
    /// @param newPrice New mimimum required price.
    function setPrice(uint256 newPrice) external onlyOperator {
        price = newPrice;
        emit PriceUpdated(newPrice);
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
