# Fixed-price Marketplace deployment

This runbook covers the Phase 2 Marketplace implementation and the native, OLAS and USDC
fixed-price factories. Choose the supported payment types for each network explicitly.
An upgrade keeps the existing Marketplace proxy and its state. A fresh deployment creates a new proxy.

## Preparation and configuration

Run from the repository root at the reviewed commit, with submodules initialized. Install Node.js 20+
and the project dependencies, Python 3, Bash, `jq`, and Foundry (`forge`, `cast`, `anvil`). The CI-pinned
Foundry version is in [workflow.yaml](../../.github/workflows/workflow.yaml). Deployment compilation
uses Solidity 0.8.30 and this checkout's `foundry.toml`; `FOUNDRY_SOLC` can point to a local 0.8.30 binary.

```sh
git submodule update --init --recursive
yarn install
npx hardhat compile
```

The shell entrypoints read `scripts/deployment/globals_<network>.json` directly. For example,
`gnosis_mainnet` selects `globals_gnosis_mainnet.json`. Review the file against the intended network
and record the previous implementation, factory addresses and configuration before deployment.
Deployment scripts save the corresponding address fields after confirmation. A nonzero configured
address blocks another deployment unless `--replace <exact previous address>` is supplied. Once the
field changes, repeating the original replacement command fails. Fresh proxy replacement is always
refused. Local attempt and confirmation records live under `.deployment-records/globals_<network>/`
in this directory and are ignored by Git; they contain addresses, transaction hashes and redacted
diagnostics, with no signing keys.

| Configuration | Meaning |
| --- | --- |
| `chainId`, `networkURL` | Expected chain ID (decimal string or number) and HTTP(S) RPC. Scripts compare the RPC chain ID before proceeding. |
| `useLedger`, `derivationPath` | Boolean wallet selection and Ledger derivation path. With `useLedger: false`, supply `PRIVATE_KEY` through the environment. |
| `contractVerification` | Boolean explorer-verification flag. When true, supply the appropriate explorer credential as `ETHERSCAN_API_KEY`; an optional `blockscoutURL` enables additional Blockscout verification. |
| `serviceRegistryAddress`, `karmaProxyAddress` | Constructor dependencies. An implementation upgrade must retain the proxy's existing dependencies. |
| `mechMarketplaceAddress`, `mechMarketplaceProxyAddress` | New implementation and existing proxy for an upgrade. The fresh-proxy step requires an absent or zero proxy address. |
| `fee`, `minResponseTimeout`, `maxResponseTimeout` | Fresh-proxy initialization parameters. An upgrade preserves the existing parameters. |
| Selected factory/tracker and asset addresses | See the payment-type table below. Trackers must point to the intended proxy and asset. |

A complete RPC URL is used as supplied. For incomplete Alchemy URLs ending in `/v2/`, the scripts
append `ALCHEMY_API_KEY_MAINNET`, `ALCHEMY_API_KEY_SEPOLIA`, `ALCHEMY_API_KEY_MATIC` or
`ALCHEMY_API_KEY_AMOY` on their respective chains. They do not require Alchemy credentials for other RPCs.

For either flow, set the network and selection to the approved rollout scope. The examples below
select native and OLAS; the presence or absence of an address in a checked-in configuration does not
define network policy.

```bash
deploymentNetwork=gnosis_mainnet
paymentTypes=(native olas)
deploymentGlobals="scripts/deployment/globals_${deploymentNetwork}.json"
```

## Existing-proxy upgrade

Record the previous implementation before authorizing its replacement:

```bash
previousImplementation=$(jq -er '.mechMarketplaceAddress' "$deploymentGlobals")
bash scripts/deployment/deploy_03_mech_marketplace.sh "$deploymentNetwork" --replace "$previousImplementation"
```

After a failure, stop and inspect the transaction as described below. Do not reset these variables
and start another deployment.

The deployed implementation must report `VERSION() == "1.2.0"`, with the expected registry and Karma
addresses. The script checks these values before saving `mechMarketplaceAddress`.

The Marketplace owner authorizes `changeImplementation(newImplementation)` on the **existing proxy**.
For a Safe or governance contract, generate the target, zero value and calldata for that owner's execution:

```bash
bash scripts/deployment/script_06_change_implementaion_mech_marketplace_proxy.sh "$deploymentNetwork" --calldata
```

`--calldata` reads the configuration and on-chain dependencies and prints the operation; it does not
use a wallet or submit a transaction. The existing filename's `implementaion` spelling is retained.
When the configured wallet is itself the Marketplace owner, omitting `--calldata` submits the transaction
and checks the receipt, implementation address, version, retained owner and legacy domain afterward.
After governance execution, perform the equivalent readbacks listed below before using the new interface.

Keep the proxy address and initialization state. The fresh-proxy step is for a separate deployment.

## Fresh Marketplace proxy

Start with an existing service registry and initialized Karma contract. Set their addresses and the
initialization parameters, with `mechMarketplaceProxyAddress` absent or zero, then run:

```bash
bash scripts/deployment/deploy_03_mech_marketplace.sh "$deploymentNetwork"
bash scripts/deployment/deploy_04_mech_marketplace_proxy.sh "$deploymentNetwork"
```

The proxy is initialized in its constructor and its initial owner is the deploying wallet. Its
implementation and owner are read back before the address is saved. The fresh-proxy script refuses
to replace an already configured proxy.

The Karma owner must authorize this new proxy using
`setMechMarketplaceStatuses([newMarketplaceProxy], [true])`. Provision each selected tracker for the
**new proxy**, and verify its asset and drainer. The registry/Karma bootstrap, tracker deployments and
ownership handover have separate authorization and configuration requirements; the shell entrypoints
updated here automate Marketplace/factory deployment and fixed-price registration. Retain an existing
tracker only when it already belongs to the intended proxy. For an existing-proxy upgrade, preserve
the existing trackers and their balances; a tracker replacement requires a separate migration plan.

## Factories and registration (both flows)

Deploy a new factory for each selected type: factories embed the updated mech creation bytecode.
The new factories point to the intended Marketplace proxy. Factory `VERSION()` remains `0.1.0`;
newly created fixed-price mechs report `1.1.0`.

| Selection | Factory deployment script | Factory configuration field | Tracker configuration field | Tracker asset field |
| --- | --- | --- | --- | --- |
| `native` | `deploy_05_mech_factory_fixed_price_native.sh` | `mechFactoryFixedPriceNativeAddress` | `balanceTrackerFixedPriceNativeAddress` | `wrappedNativeTokenAddress` |
| `olas` | `deploy_07a_mech_factory_fixed_price_token_olas.sh` | `mechFactoryFixedPriceTokenOLASAddress` | `balanceTrackerFixedPriceTokenOLASAddress` | `olasAddress` |
| `usdc` | `deploy_07b_mech_factory_fixed_price_token_usdc.sh` | `mechFactoryFixedPriceTokenUSDCAddress` | `balanceTrackerFixedPriceTokenUSDCAddress` | `usdcAddress` |

For the native/OLAS upgrade example, record the old factory addresses and explicitly replace them:

```bash
previousNativeFactory=$(jq -er '.mechFactoryFixedPriceNativeAddress' "$deploymentGlobals")
previousOlasFactory=$(jq -er '.mechFactoryFixedPriceTokenOLASAddress' "$deploymentGlobals")
bash scripts/deployment/deploy_05_mech_factory_fixed_price_native.sh "$deploymentNetwork" --replace "$previousNativeFactory"
bash scripts/deployment/deploy_07a_mech_factory_fixed_price_token_olas.sh "$deploymentNetwork" --replace "$previousOlasFactory"
```

For a fresh deployment whose factory fields are absent or zero, run the selected factory scripts with
the network argument alone. `--replace` authorizes a new contract deployment, not a retry or an update
to the old factory's bytecode.

Configure the selected trackers **before enabling the corresponding factories**. Owner wallets can
submit the following commands directly; governance owners use the same commands with `--calldata`
immediately after the network argument, and execute the resulting operations in this order:

```bash
bash scripts/deployment/script_03a_marketplace_set_balance_trackers_fixed.sh "$deploymentNetwork" "${paymentTypes[@]}"
bash scripts/deployment/script_02a_marketplace_set_factories_fixed.sh "$deploymentNetwork" "${paymentTypes[@]}"
```

Registration, including calldata generation, requires the proxy to report version `1.2.0`;
execute and confirm the upgrade first. Only selected payment types are read and submitted. Missing/invalid selected addresses fail before
submission; unselected registrations are retained. Tracker registration checks the proxy and asset.
Factory registration rebuilds the current factories with Solidity 0.8.30 and checks the full deployed
runtime code against the selected factory type's build. The expected proxy address is inserted at the
compiler-recorded immutable positions; the remaining code, including embedded mech creation code and
metadata, must match exactly. This check runs for both direct submission and calldata generation, so an
old factory or a different factory type is rejected even when its Marketplace getter is correct.
Use the same reviewed checkout and build settings for deployment and registration. Factory registration
also checks the proxy and, before direct submission, requires the selected trackers to be registered.
Calldata planning can prepare both operations before their ordered governance execution.
These commands enable the new factories; they preserve old factory statuses. Retiring an old factory
is a separate owner operation and leaves already deployed mech bytecode unchanged.

Create mechs through `Marketplace.create(serviceId, factory, payload)` after the tracker and factory
registrations are confirmed. Updating a factory does not update existing mechs. The Marketplace upgrade
must be active before using the new explicit-nonce wrapper. Clients must use the new ABI, signed deadline
and EIP-712 domain version `2`. The two sequential-nonce paths retain their legacy domain version `1.1.0`.
See [client migration](../../README.md#explicit-nonce-typed-data-signatures) for the exact signed type and selector changes.

## Confirmation and recovery

| Check after execution | Expected result |
| --- | --- |
| Proxy `getImplementation()`, Marketplace `VERSION()` | Recorded new implementation, version `1.2.0`. |
| Fresh proxy `fee()`, `minResponseTimeout()`, `maxResponseTimeout()` | Manually compare all three values with the approved initialization configuration before registration. |
| Proxy `owner()`, `serviceRegistry()`, `karma()` | Intended owner and dependencies; retained across an upgrade. |
| Proxy `getDomainSeparator()` | Same legacy separator as before the upgrade on the same chain. A mismatch requires investigation. |
| Proxy `getDomainSeparatorWithNonce()` | Standard EIP-712 hash for name `MechMarketplace`, version `2`, current chain ID and proxy address. |
| `mapPaymentTypeBalanceTrackers(type)` and tracker getters | Intended tracker, proxy and asset for each selected payment type. For a new tracker, manually verify `drainer()` against the approved fee recipient before registration. |
| `mapMechFactories(factory)` and factory `mechMarketplace()` | Enabled selected factory pointing to the intended proxy. |
| Newly created mech `VERSION()`, `paymentType()`, `mechMarketplace()` | `1.1.0`, expected payment type and proxy; explicit-nonce signing and settlement work with the updated client. |

Direct-submission scripts require a successful mined receipt and check the operation's resulting state.
Apply the network's finality policy before client cutover. Governance execution requires these same
readbacks through the owning governance process; calldata generation alone does not verify execution.

A failed deployment, receipt or deployment readback leaves the address configuration unchanged.
Before broadcasting, the script records an unresolved attempt with the chain, target, constructor
arguments, sender, transaction nonce and previous address. A second deployment is blocked while that attempt is unresolved,
even with the same `--replace` argument. Structured deployment hashes and addresses are recorded when returned, and command diagnostics are retained;
private keys, API keys and URLs are redacted from diagnostic output. If the tool provides no hash, inspect
the recorded sender's transactions on the configured chain before choosing a recovery action.

There is no automatic retry, transaction adoption or record-clearing command. After a failure:

1. Stop. Inspect the recorded transaction hash, or the sender and nonce if no hash was returned,
   on the configured chain. A timeout does not mean the transaction failed.
2. If it mined successfully, verify the creation transaction against the reviewed build and constructor
   arguments, its receipt, deployed code and the readbacks above. Record the confirmed address in the
   corresponding globals field manually; do not deploy another copy.
3. Archive the pending record only after the transaction has been accounted for. If no deployment
   succeeded, retry only after establishing that no pending transaction can still deploy the contract.

Explorer verification runs after the confirmed address is saved. If it fails, verify that saved
address separately using the same source, compiler settings and constructor arguments; do not rerun
the deployment. After an upgrade or registration failure, inspect the transaction and actual state
before retrying the owner operation. Scripts cannot roll back a mined transaction.

## Reproducing the local checks

```sh
python3 -m unittest discover -s test/deployment -p 'test_*.py' -v
node scripts/deployment/test/FixedPriceRollout.js
```

The Python suite copies the actual shell entrypoints into temporary directories and stubs `forge` and
`cast` to exercise success and failure handling without RPC access or credentials. The stubs maintain
contract state from the calls actually sent. Negative cases require the expected error, and cover each
dependency mismatch, a wrong USDC asset, missing code after deployment, a receipt for a different
transaction, and successful receipts whose state changes are missing or wrong. The Node rehearsal
uses compiled Hardhat artifacts, real Foundry commands, a temporary Anvil chain and an ephemeral wallet.
It checks fresh-proxy initialization, a legacy-proxy upgrade, governance calldata, selected registrations,
preservation of unselected settings, rejection of old/wrong-type/wrong-proxy factories in both
registration modes, and native/OLAS/USDC mech creation and signed settlement. It checks real dependency
and asset mismatches, a timeout after a real mined deployment, blocked repeat submissions,
redacted diagnostics and a simulated explorer outage. The rehearsal independently encodes both registration calls
and executes generated upgrade,
tracker and factory operations through a local 2-of-2 Safe owner while verifying the resulting state.
Neither suite uses live funds. Ledger signing, live-network configuration, production governance execution
and explorer verification still require their network-specific validation.

Historical JavaScript scripts use root-level `globals.json` and Hardhat network settings. In particular,
`deploy_12_marketplace_set_factories.js` and `deploy_13_marketplace_set_balance_trackers.js` combine
fixed-price and subscription registrations. Use the fixed-price shell entrypoints above for this rollout.
Tracker deployment, Karma, subscription and historical JavaScript tools remain outside this review.
