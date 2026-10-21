# Deployment scripts

This folder contains the scripts to deploy the contracts.

## Observations
- Shell scripts read `scripts/deployment/globals_<network>.json` directly. Historical Hardhat scripts read a separate root-level `globals.json`; do not mix the two configurations.
- Please note: if you encounter the `Unknown Error 0x6b0c`, then it is likely because the ledger is not connected or logged in.

## Steps to engage
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file, and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the following command to install the project:
```
yarn install
```
command and compiled with the
```
npx hardhat compile
```

Create a `globals.json` file in the root folder, or copy it from the file with pre-defined parameters (i.e., `scripts/deployment/globals_gnosis_mainnet.json` for the gnosis mainnet network).

Parameters of the `globals.json` file:
- `contractVerification`: a flag for verifying contracts in deployment scripts (`true`) or skipping it (`false`);
- `useLedger`: a flag whether to use the hardware wallet (`true`) or proceed with the seed-phrase accounts (`false`);
- `derivationPath`: a string with the derivation path;
- `providerName`: a network type (see `hardhat.config.js` for the network configurations);
- `networkURL`: string with the network RPC URL;
- `gasPriceInGwei`: gas price in Gwei;
- `agentType`: a mech factory type: `default` or `subscription`.

## Phase 2 upgrade of an existing Marketplace

Use a reviewed checkout with initialized submodules, compiled contracts, Foundry (`forge`, `cast`),
`jq` and Python 3. Compilation uses Solidity 0.8.30 and the checkout's `foundry.toml`.
`FOUNDRY_SOLC` may point to a local 0.8.30 compiler. Use the CI-pinned Foundry release.

This procedure retains the existing proxy, initialization state, trackers and balances. It does not
cover fresh-proxy or tracker deployment. Record the current implementation, factories, tracker
mappings, owner and legacy domain separator before starting; preserve a copy of the configuration.
Review the RPC chain ID, registry, Karma and asset addresses against the intended network.

1. Deploy the new implementation with `deploy_03_mech_marketplace.sh <network>`. The script checks
   its receipt, code, version, registry and Karma before saving the address.
2. The Marketplace owner upgrades the existing proxy using
   `script_06_change_implementaion_mech_marketplace_proxy.sh <network>`. Confirm implementation,
   version `1.2.0`, retained owner and retained legacy domain separator before continuing.
3. Deploy a new factory for each approved payment type using `deploy_05_mech_factory_fixed_price_native.sh`,
   `deploy_07a_mech_factory_fixed_price_token_olas.sh` and/or `deploy_07b_mech_factory_fixed_price_token_usdc.sh`,
   each with `<network>`. Factories embed mech bytecode, so upgrading Marketplace alone does not
   update the mechs they create. Existing deployed mechs are unchanged.
4. Enable only those types with `script_02a_marketplace_set_factories_fixed.sh <network> native olas`
   (example selection; use the approved types). This checks current factory bytecode, proxy/asset
   bindings and existing tracker mappings. Missing mappings require a separately reviewed owner
   operation; do not replace trackers or move their balances as part of this upgrade.
5. Confirm factory statuses, unchanged tracker mappings, and that newly created mechs report version
   `1.1.0`. Validate signed delivery with the updated client before cutover. The explicit-nonce path
   uses a signed deadline and domain version `2`; the two older paths retain their legacy format.

The owner scripts submit directly only when the selected signer is the Marketplace owner. A Safe
or other governance owner must use its established execution procedure for the same operations:
`changeImplementation(newImplementation)` and `setMechFactoryStatuses(selectedFactories, statuses)`.
Verify chain, proxy target, zero value, arguments, successful execution and the same state readbacks.
No governance automation is provided. Retiring old factories is a separate owner decision.

Scripts return an error on failure. A timeout may occur after a transaction mined: stop and inspect
the transaction hash, wallet transactions and actual chain state before retrying. There is no automatic
retry or recovery. A confirmed deployment is saved atomically before explorer verification; if only
verification fails, verify the saved address separately rather than deploying again. Apply the network's
finality policy before cutover. Scripts do not roll back mined transactions.

Do not run every numbered deployment script in sequence for an upgrade. Other scripts in this directory,
including fresh-proxy, tracker, subscription and legacy registration tools, are outside this procedure.

## Local validation

```sh
python3 -B -m unittest discover -s test/deployment -p 'test_*.py' -v
node scripts/deployment/test/Phase2Upgrade.js
```

The first command uses isolated fake tools to check failure handling without RPC access. The second
uses actual scripts, Foundry and a temporary Anvil chain to rehearse the upgrade and settlement with
existing trackers. Neither uses live funds. Ledger signing, production governance, explorer verification
and live network configuration still require deployment-time checks.
