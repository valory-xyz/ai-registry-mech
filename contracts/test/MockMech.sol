// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMechMarketplace {
    function deliverMarketplace(uint256 requestId, bytes memory requestData) external;
    function request(bytes memory data, uint256 priorityMechServiceId, uint256 requesterServiceId,
        uint256 responseTimeout, bytes memory paymentData) external payable returns (uint256);
}

contract MockMech {
    address public immutable mechMarketplace;

    uint256 public serviceId = 99;
    bool public isNotSelf;

    constructor(address _mechMarketplace) {
        mechMarketplace = _mechMarketplace;
    }

    function setServiceId(uint256 _serviceId) external {
        serviceId = _serviceId;
    }

    function setNotSelf(bool _isNotSelf) external {
        isNotSelf = _isNotSelf;
    }

    function deliverMarketplace(uint256 requestId, bytes memory requestData) external {
        IMechMarketplace(mechMarketplace).deliverMarketplace(requestId, requestData);
    }

    function request(
        bytes memory data,
        uint256 priorityMechServiceId,
        uint256 requesterServiceId,
        uint256 responseTimeout,
        bytes memory paymentData
    ) external payable returns (uint256) {
        return IMechMarketplace(mechMarketplace).request{value: msg.value}(data, priorityMechServiceId,
            requesterServiceId, responseTimeout, paymentData);
    }

    function tokenId() external view returns (uint256) {
        return serviceId;
    }

    function getOperator() external view returns (address) {
        if (isNotSelf) {
            return address(1);
        }

        return address(this);
    }

    function getFinalizedDeliveryRate(uint256) external pure returns (uint256) {
        return 1;
    }
}