// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1155} from "../../lib/autonolas-registries/lib/solmate/src/tokens/ERC1155.sol";

// IToken interface with ERC20 support
// Note that if the safe version is needed, make sure to update this contract
interface IToken {
    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @dev Unauthorized account.
/// @param sender Sender address.
error UnauthorizedAccount(address sender);

/// @title MockNvmSubscriptionToken - mock for creating NVM subscription based on ERC20 token
contract MockNvmSubscriptionToken is ERC1155 {
    // Token address
    address public immutable token;
    // Balance tracker address
    address public immutable balanceTracker;
    // Credit to token ratio
    uint256 public immutable creditTokenRatio;

    /// @dev MockNvmSubscriptionNative constructor.
    /// @param _token Token address.
    /// @param _balanceTracker Balance tracker address.
    /// @param _creditTokenRatio Credits to token ratio.
    constructor(address _token, address _balanceTracker, uint256 _creditTokenRatio) {
        token = _token;
        balanceTracker = _balanceTracker;
        creditTokenRatio = _creditTokenRatio;
    }

    function mint(uint256 tokenId, uint256 numCredits) external {
        uint256 requiredAmount = numCredits * creditTokenRatio / 1e18;

        _mint(msg.sender, tokenId, numCredits, "");

        IToken(token).transferFrom(msg.sender, balanceTracker, requiredAmount);
    }

    function burn(address account, uint256 tokenId, uint256 numCredits) external {
        if (msg.sender != balanceTracker && msg.sender != account) {
            revert UnauthorizedAccount(msg.sender);
        }
        _burn(account, tokenId, numCredits);
    }

    function uri(uint256) public pure override returns (string memory) {
        return "";
    }
}