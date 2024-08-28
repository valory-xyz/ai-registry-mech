// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

contract MockServiceStaking {
    enum StakingState {
        Unstaked,
        Staked,
        Evicted
    }

    // Service Info struct
    struct ServiceInfo {
        // Service multisig address
        address multisig;
        // Service owner
        address owner;
        // Service multisig nonces
        uint256[] nonces;
        // Staking start time
        uint256 tsStart;
        // Accumulated service staking reward
        uint256 reward;
        // Accumulated inactivity that might lead to the service eviction
        uint256 inactivity;
    }

    // Map service info
    mapping(uint256 => ServiceInfo) public mapServiceInfo;

    /// @dev Gets the service staking state.
    function getStakingState(uint256 serviceId) external pure returns (StakingState stakingState) {
        if (serviceId > 0) {
            return StakingState.Staked;
        }
    }

    /// @dev Sets service info.
    function setServiceInfo(uint256 serviceId, address multisig) external {
        ServiceInfo storage serviceInfo = mapServiceInfo[serviceId];
        serviceInfo.multisig = multisig;
    }

    /// @dev Gets staked service info.
    function getServiceInfo(uint256 serviceId) external view returns (ServiceInfo memory) {
        return mapServiceInfo[serviceId];
    }


    /// @dev Verifies a service staking contract instance.
    function verifyInstance(address) external pure returns (bool) {
        return true;
    }
}