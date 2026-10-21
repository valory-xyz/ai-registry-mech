// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeliverWithSignature} from "../OlasMech.sol";

interface IMechDeliveryCallbacks {
    function requestFromMarketplace(bytes32[] calldata requestIds, bytes[] calldata datas) external;
    function updateNumRequests(uint256 numRequests) external;
}

/// @dev Test-only operator. Callback calls enter the mech as its authorized service operator.
contract MockDeliveryOperator {
    address public immutable controller;
    address public immutable marketplace;

    constructor(address _marketplace) {
        controller = msg.sender;
        marketplace = _marketplace;
    }

    function execute(address mech, bytes[] calldata calls) external {
        require(msg.sender == controller, "Controller only");
        for (uint256 i = 0; i < calls.length; ++i) {
            (bool success, bytes memory result) = mech.call(calls[i]);
            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
        }
    }

    function callback(address mech, bytes calldata data) external returns (bool success, bytes memory result) {
        require(msg.sender == marketplace, "Marketplace only");
        return mech.call(data);
    }
}

/// @dev Artificial callback source for guard tests, not a reproduction against the production Marketplace.
///      Settlement and signatures are stubbed; real payments and authorization use the integration suite.
contract MockCallbackMarketplace {
    error ForcedSettlementFailure();

    address public operator;
    bytes public callbackData;
    bool public propagateFailure;
    bool public failSettlement;
    bool public callbackSucceeded;
    bytes public callbackResult;
    uint256 public settlementCalls;

    function configure(address _operator, bytes calldata data, bool propagate, bool fail) external {
        operator = _operator;
        callbackData = data;
        propagateFailure = propagate;
        failSettlement = fail;
        callbackSucceeded = false;
        delete callbackResult;
    }

    function queue(address mech, bytes32[] calldata ids, bytes[] calldata datas) external {
        IMechDeliveryCallbacks(mech).requestFromMarketplace(ids, datas);
    }

    function _settle(uint256 numRequests, bool signedDelivery) internal {
        settlementCalls++;
        // This legitimate Marketplace-only callback must work while the signed wrapper is locked.
        if (signedDelivery) {
            IMechDeliveryCallbacks(msg.sender).updateNumRequests(numRequests);
        }
        if (callbackData.length > 0) {
            bytes memory data = callbackData;
            // Attempt one nested call only, even against unguarded code.
            delete callbackData;
            (callbackSucceeded, callbackResult) = MockDeliveryOperator(operator).callback(msg.sender, data);
            if (propagateFailure && !callbackSucceeded) {
                bytes memory result = callbackResult;
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
        }
        if (failSettlement) {
            revert ForcedSettlementFailure();
        }
    }

    function deliverMarketplace(bytes32[] calldata ids, uint256[] calldata)
        external returns (bool[] memory delivered)
    {
        _settle(ids.length, false);
        delivered = new bool[](ids.length);
        for (uint256 i = 0; i < ids.length; ++i) {
            delivered[i] = true;
        }
    }

    function deliverMarketplaceWithSignatures(
        address, DeliverWithSignature[] calldata items, uint256[] calldata, bytes calldata
    ) external {
        _settle(items.length, true);
    }

    function deliverMarketplaceWithSignatures(
        address, DeliverWithSignature[] calldata items, uint256[] calldata, uint256[] calldata, bytes calldata
    ) external {
        _settle(items.length, true);
    }

    function deliverMarketplaceWithSignatures(
        address, DeliverWithSignature[] calldata items, uint256[] calldata, uint256[] memory,
        uint256[] memory, uint256[] memory, bytes calldata
    ) external {
        _settle(items.length, true);
    }
}
