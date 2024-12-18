// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Provided zero marketplace address.
error ZeroMarketplaceAddress();

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

abstract contract EscrowBase {
    event Withdraw(address indexed mech, uint256 amount);
    event Drained(uint256 collectedFees);

    // Mech marketplace address
    address public immutable mechMarketplace;

    // Collected fees
    uint256 public collectedFees;
    // Reentrancy lock
    uint256 internal _locked = 1;

    // Map of mech => its current balance
    mapping(address => uint256) public mapMechBalances;

    constructor(address _mechMarketplace) {
        // Check for zero address
        if (_mechMarketplace == address(0)) {
            revert ZeroMarketplaceAddress();
        }

        mechMarketplace = _mechMarketplace;
    }

    // Check and escrow delivery rate
    function checkAndEscrowDeliveryRate(address mech) external virtual payable;

    /// @dev Drains collected fees by sending them to a Buy back burner contract.
    function drain() external virtual;

    function adjustBalances(address mech, uint256 mechPayment, uint256 marketplaceFee) external virtual {
        if (msg.sender != mechMarketplace) {
            revert ManagerOnly(msg.sender, mechMarketplace);
        }

        // Record payment into mech balance
        mapMechBalances[mech] += mechPayment;

        // Record collected fee
        collectedFees += marketplaceFee;
    }

    /// @dev Withdraws funds for a specific mech.
    function withdraw() external virtual;
}