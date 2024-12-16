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

/// @dev No incoming msg.value is allowed.
/// @param amount Value amount.
error NoDepositAllowed(uint256 amount);

/// @dev Not enough credits to perform a request.
/// @param creditsBalance Credits balance of a sender.
/// @param minCreditsPerRequest Minimum number of credits per request needed.
error NotEnoughCredits(uint256 creditsBalance, uint256 minCreditsPerRequest);

/// @title AgentMechSubscription - Smart contract for extending AgentMech with subscription
/// @dev A Mech that is operated by the holder of an ERC721 non-fungible token via a subscription.
contract MechNeverminedSubscription is OlasMech {
    event DeliverPrice(uint256 indexed requestId, uint256 deliverPrice, uint256 creditsToBurn);
    event SubscriptionUpdated(address indexed subscriptionNFT, uint256 subscriptionTokenId);

    // Subscription NFT
    address public subscriptionNFT;
    // Subscription token Id
    uint256 public subscriptionTokenId;
    // Minimum number of credits to pay for each request via a subscription
    uint256 public minCreditsPerRequest;

    /// @dev AgentMechSubscription constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _registry Address of the token registry contract.
    /// @param _tokenId The token ID.
    /// @param _subscriptionNFT Subscription address.
    /// @param _subscriptionTokenId Subscription token Id.
    /// @param _minCreditsPerRequest Minimum number of credits to pay for each request via a subscription.
    constructor(
        address _mechMarketplace,
        address _registry,
        uint256 _tokenId,
        uint256 _minCreditsPerRequest,
        address _subscriptionNFT,
        uint256 _subscriptionTokenId
    )
        OlasMech(_mechMarketplace, _registry, _tokenId)
    {
        // Check for the subscription address
        if (_subscriptionNFT == address(0)) {
            revert ZeroAddress();
        }

        // Check for the subscription token Id
        if (_subscriptionTokenId == 0 || _minCreditsPerRequest == 0) {
            revert ZeroValue();
        }

        subscriptionNFT = _subscriptionNFT;
        subscriptionTokenId = _subscriptionTokenId;
        minCreditsPerRequest = _minCreditsPerRequest;
    }

    /// @dev Performs actions before the request is posted.
    /// @param amount Amount of payment in wei.
    function _preRequest(uint256 amount, uint256, bytes memory) internal override {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check that there is no incoming deposit
        if (amount > 0) {
            revert NoDepositAllowed(amount);
        }

        // Check for the number of credits available in the subscription vs total number of credits needed
        uint256 creditsBalance = IERC1155(subscriptionNFT).balanceOf(msg.sender, subscriptionTokenId);
        uint256 numUndeliveredRequests = mapUndeliveredRequestsCounts[msg.sender];
        uint256 creditsPerPendingRequests = (numUndeliveredRequests + 1) * minCreditsPerRequest;
        if (creditsBalance < creditsPerPendingRequests) {
            revert NotEnoughCredits(creditsBalance, creditsPerPendingRequests);
        }

        _locked = 1;
    }

    /// @dev Performs actions before the delivery of a request.
    /// @param account Request sender address.
    /// @param requestId Request Id.
    /// @param data Self-descriptive opaque data-blob.
    /// @return requestData Data for the request processing.
    function _preDeliver(
        address account,
        uint256 requestId,
        bytes memory data
    ) internal override returns (bytes memory requestData) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Extract the request deliver price
        uint256 deliverPrice;
        (deliverPrice, requestData) = abi.decode(data, (uint256, bytes));

        // Check for the number of credits available in the subscription
        uint256 creditsBalance = IERC1155(subscriptionNFT).balanceOf(account, subscriptionTokenId);

        // Adjust the amount of credits to burn if the deliver price is bigger than the amount of credits available
        uint256 creditsToBurn = deliverPrice;
        if (creditsToBurn > creditsBalance) {
            creditsToBurn = creditsBalance;
        }

        // Burn credits of the request Id sender upon delivery
        if (creditsToBurn > 0) {
            IERC1155(subscriptionNFT).burn(account, subscriptionTokenId, creditsToBurn);
        }

        emit DeliverPrice(requestId, deliverPrice, creditsToBurn);

        _locked = 1;
    }

    /// @dev Sets a new subscription.
    /// @param newSubscriptionNFT New address of the NFT subscription.
    /// @param newSubscriptionTokenId New subscription Id.
    /// @param newMinCreditsPerRequest New minimum number of credits to pay for each request via a subscription.
    function setSubscription(
        address newSubscriptionNFT,
        uint256 newSubscriptionTokenId,
        uint256 newMinCreditsPerRequest
    ) external onlyOperator {
        // Check for the subscription address
        if (newSubscriptionNFT == address(0)) {
            revert ZeroAddress();
        }

        // Check for the subscription token Id
        if (newSubscriptionTokenId == 0 || newMinCreditsPerRequest == 0) {
            revert ZeroValue();
        }

        subscriptionNFT = newSubscriptionNFT;
        subscriptionTokenId = newSubscriptionTokenId;
        minCreditsPerRequest = newMinCreditsPerRequest;

        emit SubscriptionUpdated(subscriptionNFT, subscriptionTokenId);
    }
}