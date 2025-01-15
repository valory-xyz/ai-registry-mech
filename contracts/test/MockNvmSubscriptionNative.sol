// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1155} from "../../lib/autonolas-registries/lib/solmate/src/tokens/ERC1155.sol";

/// @dev Not enough balance to cover costs.
/// @param current Current balance.
/// @param required Required balance.
error InsufficientBalance(uint256 current, uint256 required);

/// @dev Unauthorized account.
/// @param sender Sender address.
error UnauthorizedAccount(address sender);

/// @title MockNvmSubscriptionNative - mock for creating NVM subscription based on native token
contract MockNvmSubscriptionNative is ERC1155 {
    // Balance tracker address
    address public immutable balanceTracker;
    // Credit to token ratio
    uint256 public immutable creditTokenRatio;

    /// @dev MockNvmSubscriptionNative constructor.
    /// @param _creditTokenRatio Credits to token ratio.
    constructor(address _balanceTracker, uint256 _creditTokenRatio) {
        balanceTracker = _balanceTracker;
        creditTokenRatio = _creditTokenRatio;
    }

    function mint(uint256 tokenId, uint256 numCredits) external payable {
        uint256 requiredAmount = numCredits * creditTokenRatio;

        if (msg.value < requiredAmount) {
            revert InsufficientBalance(msg.value, requiredAmount);
        }

        _mint(msg.sender, tokenId, numCredits, "");

        balanceTracker.call{value: msg.value}("");
    }

    function burn(address account, uint256 tokenId, uint256 numCredits) external {
        if (msg.sender != balanceTracker && msg.sender != account) {
            revert UnauthorizedAccount(msg.sender);
        }
        _burn(account, tokenId, numCredits);
    }

    function uri(uint256 id) public view override returns (string memory) {
        return "";
    }
}