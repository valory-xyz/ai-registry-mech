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

    // Map of requests counts for corresponding addresses
    mapping (address => uint256) public mapRequestsCounts;

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

        price = _price;
    }

    /// @dev Registers a request.
    /// @param data Self-descriptive opaque data-blob.
    function request(bytes memory data) external payable returns (uint256 requestId) {
        if (msg.value < price) {
            revert NotEnoughPaid(msg.value, price);
        }

        requestId = getRequestId(msg.sender, data);
        mapRequestsCounts[msg.sender]++;
        emit Request(msg.sender, requestId, data);
    }

    /// @dev Delivers a request.
    /// @param requestId Request id.
    /// @param data Self-descriptive opaque data-blob.
    function deliver(uint256 requestId, bytes memory data) external onlyOperator {
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
}
