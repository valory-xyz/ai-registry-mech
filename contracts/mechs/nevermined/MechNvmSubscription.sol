// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OlasMech} from "../../OlasMech.sol";

interface IERC1155 {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @param tokenId Token Id.
    /// @return Amount of tokens owned.
    function balanceOf(address account, uint256 tokenId) external view returns (uint256);

    /// @dev Burns a specified amount of account's tokens.
    /// @param account Account address.
    /// @param tokenId Token Id.
    /// @param amount Amount of tokens.
    function burn(address account, uint256 tokenId, uint256 amount) external;
}

/// @dev Provided zero subscription address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @title MechNvmSubscription - Smart contract for extending OlasMech with Nevermided subscription
/// @dev A Mech that is operated by the holder of an ERC721 non-fungible token via a Nevermided subscription.
contract MechNvmSubscription is OlasMech {
    event RequestRateFinalized(uint256 indexed requestId, uint256 deliveryRate);

    // keccak256(NvmSubscription) = 626e3e03bc0d3f35fa97066f92f71221d599a2bcf50a2c9d6cfa6572204006a0
    bytes32 public constant PAYMENT_TYPE = 0x626e3e03bc0d3f35fa97066f92f71221d599a2bcf50a2c9d6cfa6572204006a0;

    // Mapping for requestId => finalized delivery rates
    mapping(uint256 => uint256) public mapRequestIdFinalizedRates;

    /// @dev MechNvmSubscription constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _serviceRegistry Address of the token contract.
    /// @param _serviceId Service Id.
    /// @param _maxDeliveryRate The maximum delivery rate.
    constructor(address _mechMarketplace, address _serviceRegistry, uint256 _serviceId,uint256 _maxDeliveryRate)
        OlasMech(_mechMarketplace, _serviceRegistry, _serviceId, _maxDeliveryRate, PAYMENT_TYPE)
    {}

    /// @dev Performs actions before the delivery of a request.
    /// @param requestId Request Id.
    /// @param data Self-descriptive opaque data-blob.
    /// @return requestData Data for the request processing.
    function _preDeliver(
        uint256 requestId,
        bytes memory data
    ) internal override returns (bytes memory requestData) {
        // Extract the request deliver rate as credits to burn
        uint256 deliveryRate;
        (deliveryRate, requestData) = abi.decode(data, (uint256, bytes));

        mapRequestIdFinalizedRates[requestId] = deliveryRate;

        emit RequestRateFinalized(requestId, deliveryRate);
    }

    /// @dev Gets finalized delivery rate for a request Id.
    /// @param requestId Request Id.
    /// @return Finalized delivery rate.
    function getFinalizedDeliveryRate(uint256 requestId) public virtual override returns (uint256) {
        return mapRequestIdFinalizedRates[requestId];
    }
}
