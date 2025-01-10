// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Mech interface
interface IMech {
    /// @dev Registers marketplace requests.
    /// @param requester Requester address.
    /// @param requestIds Set of request Ids.
    /// @param datas Set of corresponding self-descriptive opaque data-blobs.
    function requestFromMarketplace(address requester, uint256[] memory requestIds, bytes[] memory datas) external;

    /// @dev Updates number of requests delivered directly via Marketplace.
    /// @param numRequests Number of requests.
    function updateNumRequests(uint256 numRequests) external;

    /// @dev Gets mech max delivery rate.
    /// @return Mech maximum delivery rate.
    function maxDeliveryRate() external returns (uint256);

    /// @dev Gets mech payment type hash.
    /// @return Mech payment type hash.
    function paymentType() external returns (bytes32);

    /// @dev Gets finalized delivery rate for a request Id.
    /// @param requestId Request Id.
    /// @return Finalized delivery rate.
    function getFinalizedDeliveryRate(uint256 requestId) external returns (uint256);

    /// @dev Gets mech token Id (service Id).
    /// @return serviceId Service Id.
    function tokenId() external view returns (uint256);

    /// @dev Gets mech operator (service multisig).
    /// @return Service multisig address.
    function getOperator() external view returns (address);

    /// @dev Checks the mech operator (service multisig).
    /// @param multisig Service multisig being checked against.
    /// @return True, if mech service multisig matches the provided one.
    function isOperator(address multisig) external view returns (bool);
}