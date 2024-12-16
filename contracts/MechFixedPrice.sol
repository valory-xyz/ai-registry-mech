// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OlasMech} from "./OlasMech.sol";

/// @title MechFixedPrice - Smart contract for OlasMech that accepts a fixed price payment for services.
contract MechFixedPrice is OlasMech {
    event PriceUpdated(uint256 price);

    // Minimum required price
    uint256 public price;

    /// @dev AgentMech constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _serviceRegistry Address of the token contract.
    /// @param _serviceId Service Id.
    /// @param _price The minimum required price.
    constructor(address _mechMarketplace, address _serviceRegistry, uint256 _serviceId, uint256 _price)
        OlasMech(_mechMarketplace, _serviceRegistry, _serviceId)
    {
        // Check for zero value
        if (price == 0) {
            revert ZeroValue();
        }

        // Record the price
        price = _price;
    }

    /// @dev Performs actions before the request is posted.
    /// @param amount Amount of payment in wei.
    function _preRequest(uint256 amount, uint256, bytes memory) internal virtual override {
        // Check the request payment
        if (amount < price) {
            revert NotEnoughPaid(amount, price);
        }
    }

    /// @dev Performs actions before the delivery of a request.
    /// @param data Self-descriptive opaque data-blob.
    /// @return requestData Data for the request processing.
    function _preDeliver(address, uint256, bytes memory data) internal virtual override returns (bytes memory requestData) {
        requestData = data;
    }


    /// @dev Sets the new price.
    /// @param newPrice New mimimum required price.
    function setPrice(uint256 newPrice) external onlyOperator {
        // Check for zero value
        if (price == 0) {
            revert ZeroValue();
        }

        price = newPrice;
        emit PriceUpdated(newPrice);
    }
}
