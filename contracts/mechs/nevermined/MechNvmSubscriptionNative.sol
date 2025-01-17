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

/// @title MechNvmSubscriptionNative - Smart contract for extending OlasMech with Nevermided subscription based on native token
/// @dev A Mech that is operated by the holder of an ERC721 non-fungible token via a Nevermided subscription.
contract MechNvmSubscriptionNative is OlasMech {
    event RequestRateFinalized(bytes32 indexed requestId, uint256 deliveryRate);

    // keccak256(NvmSubscriptionNative) = 803dd08fe79d91027fc9024e254a0942372b92f3ccabc1bd19f4a5c2b251c316
    bytes32 public constant PAYMENT_TYPE = 0x803dd08fe79d91027fc9024e254a0942372b92f3ccabc1bd19f4a5c2b251c316;

    // Mapping for requestId => finalized delivery rates
    mapping(bytes32 => uint256) public mapRequestIdFinalizedRates;

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
        bytes32 requestId,
        bytes memory data
    ) internal override returns (bytes memory requestData) {
        // Extract the request deliver rate as credits to burn
        uint256 deliveryRate;
        (deliveryRate, requestData) = abi.decode(data, (uint256, bytes));

        mapRequestIdFinalizedRates[requestId] = deliveryRate;

        emit RequestRateFinalized(requestId, deliveryRate);
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
            deliveryRates[i] = mapRequestIdFinalizedRates[requestIds[i]];
        }
    }
}
