# Deployment scripts

This folder contains the scripts to deploy the contracts.

## Observations
- There are several files with global parameters based on the corresponding network. In order to work with the configuration, please copy `gobals_network.json` file to file the `gobals.json` one, where `network` is the corresponding network. For example: `cp gobals_gnosis.json gobals.json`.
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

Create a `globals.json` file in the root folder, or copy it from the file with pre-defined parameters (i.e., `scripts/deployment/globals_gnosis.json` for the gnosis network).

Parameters of the `globals.json` file:
- `contractVerification`: a flag for verifying contracts in deployment scripts (`true`) or skipping it (`false`);
- `useLedger`: a flag whether to use the hardware wallet (`true`) or proceed with the seed-phrase accounts (`false`);
- `derivationPath`: a string with the derivation path;
- `providerName`: a network type (see `hardhat.config.js` for the network configurations);

The script file name identifies the number of deployment steps taken from / to the number in the file name. For example:
- `deploy_01_agent_registry.js` will complete step 1.

NOTE: All the scripts MUST be strictly run in the sequential order from smallest to biggest numbers.
NOTE: AgentMech MUST NOT be deployed by its own script, as each AgentMech is created via the AgentFactory contract.
The `test_purposes_only_deploy_04_agent_mech.js` is provided strictly for testing purposes.

Export network-related API keys defined in `hardhat.config.js` file that correspond to the required network.

To run the script, use the following command:
`npx hardhat run scripts/deployment/script_name --network network_type`,
where `script_name` is a script name, i.e. `deploy_01_agent_registry.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration.

## Validity checks and contract verification
Each script controls the obtained values by checking them against the expected ones. Also, each script has a contract verification procedure.
If a contract is deployed with arguments, these arguments are taken from the corresponding `verify_number_and_name` file, where `number_and_name` corresponds to the deployment script number and name.

To verify a mech use `e_check_04_agent_mech.js` and first ensure that `globals.json` contains the mech data, e.g: `"agentMechAddress":"0x3504fb5053ec12f748017248a395b4ed31739705","agentId":1,"price":"10000000000000000"`
