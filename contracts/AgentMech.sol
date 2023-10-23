// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC721Mech} from "../lib/mech/contracts/ERC721Mech.sol";

interface IToken {
    /// @dev Gets the owner of the `tokenId` token.
    /// @param tokenId Token Id that must exist.
    /// @return tokenOwner Token owner.
    function ownerOf(uint256 tokenId) external view returns (address tokenOwner);
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

/// @title AgentMech - Smart contract for extending ERC721Mech
/// @dev A Mech that is operated by the holder of an ERC721 non-fungible token.
contract AgentMech is ERC721Mech {
    event Perform(address indexed sender, bytes32 taskHash);
    event Deliver(address indexed sender, uint256 requestId, bytes data);
    event Request(address indexed sender, uint256 requestId, bytes data);
    event PriceUpdated(uint256 price);

    // Minimum required price
    uint256 public price;
    // Number of undelivered requests
    uint256 public numUndeliveredRequests;

    // Map of requests counts for corresponding addresses
    mapping (address => uint256) public mapRequestsCounts;
    // Map of request Ids
    mapping (uint256 => uint256[2]) public mapRequestIds;

    /// @dev AgentMech constructor.
    /// @param _token Address of the token contract.
    /// @param _tokenId The token ID.
    /// @param _price The minimum required price.
    constructor(address _token, uint256 _tokenId, uint256 _price) ERC721Mech(_token, _tokenId) {
        // Check for the token address
        if (_token == address(0)) {
            revert ZeroAddress();
        }

        // Check for the token to have the owner
        address tokenOwner = IToken(_token).ownerOf(_tokenId);
        if (tokenOwner == address(0)) {
            revert AgentNotFound(_tokenId);
        }

        // Record the price
        price = _price;
    }

    /// @dev Registers a request.
    /// @param data Self-descriptive opaque data-blob.
    function request(bytes memory data) external payable returns (uint256 requestId) {
        if (msg.value < price) {
            revert NotEnoughPaid(msg.value, price);
        }

        // Get the request Id
        requestId = getRequestId(msg.sender, data);
        // Increase the requests count supplied by the sender
        mapRequestsCounts[msg.sender]++;

        // Record the request Id in the map
        // Get previous and next request Ids of the first element
        uint256[2] storage requestIds = mapRequestIds[0];
        // Create the new element
        uint256[2] storage newRequestIds = mapRequestIds[requestId];

        // Previous element will be zero, next element will be the current next element
        uint256 curNextRequestId = requestIds[1];
        newRequestIds[1] = curNextRequestId;
        // Next element of the zero element will be the newly created element
        requestIds[1] = requestId;
        // Previous element of the current next element will be the newly created element
        mapRequestIds[curNextRequestId][0] = requestId;

        // Check for the previous element of the zero one to exist, and if there is none - assign the newly created one
        if (requestIds[0] == 0) {
            requestIds[0] = requestId;
        }
        // Increase the number of undelivered requests
        numUndeliveredRequests++;

        emit Request(msg.sender, requestId, data);
    }

    /// @dev Delivers a request.
    /// @param requestId Request id.
    /// @param data Self-descriptive opaque data-blob.
    function deliver(uint256 requestId, bytes memory data) external onlyOperator {
        // Remove delivered request Id from the request Ids map
        uint256[2] memory requestIds = mapRequestIds[requestId];
        // Re-link previous and next elements between themselves
        mapRequestIds[requestIds[0]][1] = requestIds[1];
        mapRequestIds[requestIds[1]][0] = requestIds[0];
        // Delete the delivered element from the map
        delete mapRequestIds[requestId];
        // Decrease the number of undelivered requests
        numUndeliveredRequests--;

        emit Deliver(msg.sender, requestId, data);
    }

    /// @dev Sets the new price.
    /// @param newPrice New mimimum required price.
    function setPrice(uint256 newPrice) external onlyOperator {
        price = newPrice;
        emit PriceUpdated(newPrice);
    }

    /// @dev Gets the request Id.
    /// @param account Account address.
    /// @param data Self-descriptive opaque data-blob.
    /// @return requestId Corresponding request Id.
    function getRequestId(address account, bytes memory data) public pure returns (uint256 requestId) {
        requestId = uint256(keccak256(abi.encode(account, data)));
    }

    /// @dev Gets the requests count for a specific account.
    /// @param account Account address.
    /// @return requestsCount Requests count.
    function getRequestsCount(address account) external view returns (uint256 requestsCount) {
        requestsCount = mapRequestsCounts[account];
    }

    /// @dev Gets the set of undelivered request Ids.
    /// @return requestIds Set of undelivered request Ids.
    function getUndeliveredRequestIds() external view returns (uint256[] memory requestIds) {
        uint256 numRequests = numUndeliveredRequests;
        requestIds = new uint256[](numRequests);

        // The first request Id is the next request Id of the zero element in the request Ids map
        uint256 curRequestId = mapRequestIds[0][1];
        for (uint256 i = 0; i < numRequests; ++i) {
            requestIds[i] = curRequestId;
            curRequestId = mapRequestIds[curRequestId][1];
        }
    }
}
