// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1155TokenReceiver} from "../../../lib/autonolas-registries/lib/solmate/src/tokens/ERC1155.sol";
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

contract BalanceTrackerSubscription is ERC1155TokenReceiver {

    // Mech marketplace address
    address public immutable mechMarketplace;
    // Subscription NFT
    address public immutable subscriptionNFT;
    // Subscription token Id
    uint256 public immutable subscriptionTokenId;

    // Reentrancy lock
    uint256 internal _locked = 1;

    /// @dev BalanceTrackerSubscription constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _subscriptionNFT Subscription NFT address.
    /// @param _subscriptionTokenId Subscription token Id.
    /// @param _paymentType Mech payment type.
    constructor(address _mechMarketplace, address _subscriptionNFT, uint256 _subscriptionTokenId, uint8 _paymentType){
        if (_subscriptionNFT == address(0)) {
            revert ZeroAddress();
        }

        if (_subscriptionTokenId == 0) {
            revert ZeroValue();
        }

        mechMarketplace = _mechMarketplace;
        subscriptionNFT = _subscriptionNFT;
        subscriptionTokenId = _subscriptionTokenId;
        paymentType = _paymentType;
    }

    // Check and record delivery rate
    function checkAndRecordDeliveryRate(address mech, bytes memory paymentData) external virtual override payable {
        uint256 maxDeliveryRate = IMech(mech).maxDeliveryRate();

        // Check that there is no incoming deposit
        if (msg.value > 0) {
            revert NoDepositAllowed(msg.value);
        }

        // TODO Probably just check the amount of credits on a subscription for a msg.sender, as it's going to be managed by Nevermined
        // Get max subscription delivery rate from sender
        IERC1155(subscriptionNFT).safeTransferFrom(msg.sender, address(this), subscriptionTokenId, maxDeliveryRate, "");
    }

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