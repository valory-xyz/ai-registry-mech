// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1155TokenReceiver} from "../../../lib/autonolas-registries/lib/solmate/src/tokens/ERC1155.sol";
import {EscrowBase} from "../../EscrowBase.sol";
import {IMech} from "../../interfaces/IMech.sol";

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

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Account is unauthorized.
/// @param account Account address.
error UnauthorizedAccount(address account);

/// @dev No incoming msg.value is allowed.
/// @param amount Value amount.
error NoDepositAllowed(uint256 amount);

contract EscrowSubscription is EscrowBase, ERC1155TokenReceiver {
    event SubscriptionUpdated(address indexed subscriptionNFT, uint256 subscriptionTokenId);

    // Subscription NFT
    address public immutable subscriptionNFT;
    // Subscription token Id
    uint256 public immutable subscriptionTokenId;

    constructor(address _mechMarketplace, address _subscriptionNFT, uint256 _subscriptionTokenId)
        EscrowBase(_mechMarketplace)
    {
        if (_subscriptionNFT == address(0)) {
            revert ZeroAddress();
        }

        if (_subscriptionTokenId == 0) {
            revert ZeroValue();
        }

        subscriptionNFT = _subscriptionNFT;
        subscriptionTokenId = _subscriptionTokenId;
    }

    // Check and escrow delivery rate
    function checkAndRecordDeliveryRate(address mech, bytes memory paymentData) external virtual override payable {
        uint256 maxDeliveryRate = IMech(mech).maxDeliveryRate();

        // Check that there is no incoming deposit
        if (msg.value > 0) {
            revert NoDepositAllowed(msg.value);
        }

        // TODO Probably just check the amount of credits on a subscription for a msg.sender, as it's going to be managed by Nevermined
        // Get max subscription rate for escrow from sender
        IERC1155(subscriptionNFT).safeTransferFrom(msg.sender, address(this), subscriptionTokenId, maxDeliveryRate, "");
    }

    // TODO TBD
    /// @dev Drains collected fees by sending them to a Buy back burner contract.
    function drain() external virtual override {}

    /// @dev Withdraws funds for a specific mech.
    function withdraw() external virtual override {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get mech balance
        uint256 balance = mapMechBalances[msg.sender];
        if (balance == 0) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Transfer mech balance
        IERC1155(subscriptionNFT).safeTransferFrom(address(this), msg.sender, subscriptionTokenId, balance, "");

        emit Withdraw(msg.sender, balance);

        _locked = 1;
    }
}