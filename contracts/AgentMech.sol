// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721Mech} from "../lib/mech/contracts/ERC721Mech.sol";

/// @dev Not enough value paid.
/// @param provided Provided amount.
/// @param expected Expected amount.
error NotEnoughPaid(uint256 provided, uint256 expected);

/// @title AgentMech - Smart contract for extending ERC721Mech
/// @dev A Mech that is operated by the holder of an ERC721 non-fungible token.
contract AgentMech is ERC721Mech {
    event Perform(address indexed sender, bytes32 taskHash);
    event Deliver(uint256 requestId, bytes data);
    event Request(address indexed sender, uint256 requestId, bytes data);
    event PriceUpdated(uint256 price);

    // Minimum required price
    uint256 public price;

    /// @dev AgentMech constructor.
    /// @param _token Address of the token contract.
    /// @param _tokenId The token ID.
    /// @param _price The minimum required price.
    constructor(address _token, uint256 _tokenId, uint256 _price) ERC721Mech(_token,_tokenId) {
        price = _price;
    }

    /// @dev Registers a request.
    /// @param data Self-descriptive opaque data-blob.
    function request(bytes memory data) external payable returns (uint256 requestId) {
        if (msg.value < price) {
            revert NotEnoughPaid(msg.value, price);
        }

        requestId = getRequestId(msg.sender, data);
        emit Request(msg.sender, requestId, data);
    }

    /// @dev Delivers a request.
    /// @param requestId Request id.
    /// @param data Self-descriptive opaque data-blob.
    function deliver(uint256 requestId, bytes memory data) external onlyOperator {
        emit Deliver(requestId, data);
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
}
