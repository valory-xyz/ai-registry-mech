// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OlasMech} from "./OlasMech.sol";

/// @title MechFixedPriceBase - Smart contract for OlasMech that accepts a fixed price payment for services.
abstract contract MechFixedPriceBase is OlasMech {
    /// @dev MechFixedPriceBase constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _serviceRegistry Address of the token contract.
    /// @param _serviceId Service Id.
    /// @param _maxDeliveryRate The maximum delivery rate.
    /// @param _paymentType Payment type.
    constructor(address _mechMarketplace, address _serviceRegistry, uint256 _serviceId, uint256 _maxDeliveryRate, bytes32 _paymentType)
        OlasMech(_mechMarketplace, _serviceRegistry, _serviceId, _maxDeliveryRate, _paymentType)
    {}

    /// @dev Performs actions before the delivery of a request.
    /// @param data Self-descriptive opaque data-blob.
    /// @return requestData Data for the request processing.
    function _preDeliver(bytes32, bytes memory data) internal virtual override returns (bytes memory requestData) {
        requestData = data;
    }

    /// @dev Gets finalized delivery rate for request Ids.
    /// @param requestIds Set of request Ids.
    /// @return deliveryRates Set of corresponding finalized delivery rates.
    function getFinalizedDeliveryRates(
        bytes32[] memory requestIds
    ) public view virtual override returns (uint256[] memory deliveryRates) {
        uint256 numRequests = requestIds.length;
        deliveryRates = new uint256[](numRequests);

        for (uint256 i = 0; i < numRequests; ++i) {
            deliveryRates[i] = maxDeliveryRate;
        }
    }
}
