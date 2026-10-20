// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MarketplaceDomainTestBase} from "./MechMarketplaceDomainSeparator.t.sol";
import {MechMarketplace} from "../contracts/MechMarketplace.sol";
import {MechMarketplaceProxy} from "../contracts/proxies/MechMarketplaceProxy.sol";

/// @dev Opt-in: RUN_MARKETPLACE_DOMAIN_FORKS=true forge test --match-contract ForkMechMarketplaceDomainSeparatorTest ...
///      All upgrades are simulated on local forks. No transaction is broadcast.
contract ForkMechMarketplaceDomainSeparatorTest is MarketplaceDomainTestBase {
    event log_named_uint(string key, uint256 value);

    function _checkFork(string memory name) internal {
        vm.skip(!vm.envOr("RUN_MARKETPLACE_DOMAIN_FORKS", false));
        string memory pins = vm.readFile("test/fixtures/domain-separator-forks.json");
        string memory key = string.concat(".", name);
        uint256 id = vm.parseJsonUint(pins, string.concat(key, ".chainId"));
        uint256 number = vm.parseJsonUint(pins, string.concat(key, ".blockNumber"));
        uint256 evmNumber = vm.parseJsonUint(pins, string.concat(key, ".evmBlockNumber"));
        address proxy = vm.parseJsonAddress(pins, string.concat(key, ".proxy"));
        vm.createSelectFork(vm.parseJsonString(pins, string.concat(key, ".rpc")), number);
        emit log_named_uint("fork chain ID", block.chainid);
        emit log_named_uint("EVM block number", block.number);
        require(block.chainid == id, "wrong fork chain");
        // Arbitrum exposes the L1 number to BLOCKNUMBER, while RPC/fork selection uses its L2 height.
        require(block.number == evmNumber, "wrong fork block");
        require(block.timestamp == vm.parseJsonUint(pins, string.concat(key, ".timestamp")), "wrong fork timestamp");
        require(proxy.code.length > 0, "proxy has no code");
        MechMarketplace marketplace = MechMarketplace(proxy);
        bytes32 expected = _domain(id, proxy);
        require(marketplace.domainSeparator() == expected, "stored domain differs: investigate before upgrade");
        require(marketplace.getDomainSeparator() == expected, "live getter differs");
        address registry = marketplace.serviceRegistry();
        address karma = marketplace.karma();
        address owner = marketplace.owner();
        require(owner != address(0), "uninitialized proxy");
        address oldImplementation = MechMarketplaceProxy(payable(proxy)).getImplementation();
        require(oldImplementation.code.length > 0, "old implementation has no code");
        bytes32 storageBefore = _rootStorage(proxy);
        uint256 nonceBefore = marketplace.mapNonces(owner);
        uint256 requestsBefore = marketplace.mapRequestCounts(owner);
        bytes32 requestBefore =
            marketplace.getRequestId(address(1), owner, hex"1234", 100, bytes32(uint256(1)), nonceBefore);
        address candidate = _candidate(registry, karma);
        vm.prank(owner);
        marketplace.changeImplementation(candidate);
        require(MechMarketplaceProxy(payable(proxy)).getImplementation() == candidate, "upgrade not applied");
        require(_rootStorage(proxy) == storageBefore, "proxy root storage changed");
        require(marketplace.owner() == owner, "owner changed");
        require(
            marketplace.serviceRegistry() == registry && marketplace.karma() == karma, "immutable dependencies changed"
        );
        require(
            marketplace.domainSeparator() == expected && marketplace.getDomainSeparator() == expected, "domain changed"
        );
        require(marketplace.mapNonces(owner) == nonceBefore, "nonce mapping changed");
        require(marketplace.mapRequestCounts(owner) == requestsBefore, "request mapping changed");
        require(
            marketplace.getRequestId(address(1), owner, hex"1234", 100, bytes32(uint256(1)), nonceBefore)
                == requestBefore,
            "legacy request digest changed"
        );
    }

    function test_mainnetUpgrade() public {
        _checkFork("mainnet");
    }

    function test_gnosisUpgrade() public {
        _checkFork("gnosis");
    }

    function test_baseUpgrade() public {
        _checkFork("base");
    }

    function test_polygonUpgrade() public {
        _checkFork("polygon");
    }

    function test_optimismUpgrade() public {
        _checkFork("optimism");
    }

    function test_arbitrumUpgrade() public {
        _checkFork("arbitrum");
    }

    function test_celoUpgrade() public {
        _checkFork("celo");
    }

    function test_robinhoodUpgrade() public {
        _checkFork("robinhood");
    }
}
