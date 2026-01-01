/*global process*/

const { ethers } = require("ethers");
const { expect } = require("chai");
const fs = require("fs");

const verifyRepo = false;
const verifySetup = true;

// Custom expect that is wrapped into try / catch block
function customExpect(arg1, arg2, log) {
    try {
        expect(arg1).to.equal(arg2);
    } catch (error) {
        console.log(log);
        if (error.status) {
            console.error(error.status);
            console.log("\n");
        } else {
            console.error(error);
            console.log("\n");
        }
    }
}

// Custom expect for contain clause that is wrapped into try / catch block
function customExpectContain(arg1, arg2, log) {
    try {
        expect(arg1).contain(arg2);
    } catch (error) {
        console.log(log);
        if (error.status) {
            console.error(error.status);
            console.log("\n");
        } else {
            console.error(error);
            console.log("\n");
        }
    }
}

// Check the bytecode
async function checkBytecode(provider, configContracts, contractName, log) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Get the contract instance
            const contractFromJSON = fs.readFileSync(configContracts[i]["artifact"], "utf8");
            const parsedFile = JSON.parse(contractFromJSON);
            // Forge JSON
            let bytecode = parsedFile["deployedBytecode"]["object"];
            if (bytecode === undefined) {
                // Hardhat JSON
                bytecode = parsedFile["deployedBytecode"];
            }
            const onChainCreationCode = await provider.getCode(configContracts[i]["address"]);
            // Bytecode DEBUG
            //if (contractName === "ContractName") {
            //    console.log("onChainCreationCode", onChainCreationCode);
            //    console.log("bytecode", bytecode);
            //}

            // Compare last 43 bytes as they reflect the deployed contract metadata hash
            // We cannot compare the full one since the repo deployed bytecode does not contain immutable variable info
            customExpectContain(onChainCreationCode, bytecode.slice(-86),
                log + ", address: " + configContracts[i]["address"] + ", failed bytecode comparison");
            return;
        }
    }
}

// Find the contract name from the configuration data
async function findContractInstance(provider, configContracts, contractName) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Get the contract instance
            let contractFromJSON = fs.readFileSync(configContracts[i]["artifact"], "utf8");

            // Additional step for proxy contracts
            if (contractName === "KarmaProxy" || contractName === "MechMarketplaceProxy") {
                // Get previous ABI
                contractFromJSON = fs.readFileSync(configContracts[i - 1]["artifact"], "utf8");
            }

            const parsedFile = JSON.parse(contractFromJSON);
            const abi = parsedFile["abi"];
            const contractInstance = new ethers.Contract(configContracts[i]["address"], abi, provider);
            return contractInstance;
        }
    }
}

// Check KarmaProxy: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkKarmaProxy(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const karmaProxy = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + karmaProxy.address;
    // Check the owner
    const owner = await karmaProxy.owner();
    customExpect(owner, globalsInstance["bridgeMediatorAddress"], log + ", function: owner()");

    // Check the whitelisted marketplace
    const isMarketplaceWhitelisted = await karmaProxy.mapMechMarketplaces(globalsInstance["mechMarketplaceProxyAddress"]);
    customExpect(isMarketplaceWhitelisted, true, log + ", function: mapMechMarketplaces()");
}

// Check MechMarketplaceProxy: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkMechMarketplaceProxy(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const mechMarketplaceProxy = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + mechMarketplaceProxy.address;
    // Check the owner
    const owner = await mechMarketplaceProxy.owner();
    customExpect(owner, globalsInstance["bridgeMediatorAddress"], log + ", function: owner()");

    // Check service registry address
    const serviceRegistry = await mechMarketplaceProxy.serviceRegistry();
    customExpect(serviceRegistry, globalsInstance["serviceRegistryAddress"], log + ", function: serviceRegistry()");

    // Check karma address
    const karma = await mechMarketplaceProxy.karma();
    customExpect(karma, globalsInstance["karmaProxyAddress"], log + ", function: karma()");

    // Check fee
    const fee = await mechMarketplaceProxy.fee();
    customExpect(fee.toString(), globalsInstance["fee"], log + ", function: fee()");

    // Check min response time
    const minResponseTimeout = await mechMarketplaceProxy.minResponseTimeout();
    customExpect(minResponseTimeout.toString(), globalsInstance["minResponseTimeout"], log + ", function: minResponseTimeout()");

    // Check max response time
    const maxResponseTimeout = await mechMarketplaceProxy.maxResponseTimeout();
    customExpect(maxResponseTimeout.toString(), globalsInstance["maxResponseTimeout"], log + ", function: maxResponseTimeout()");

    // Check whitelisted factories
    let isFactoryWhitelisted = await mechMarketplaceProxy.mapMechFactories(globalsInstance["mechFactoryFixedPriceNativeAddress"]);
    customExpect(isFactoryWhitelisted, true, log + ", function: mapMechFactories()");
    isFactoryWhitelisted = await mechMarketplaceProxy.mapMechFactories(globalsInstance["mechFactoryFixedPriceTokenAddress"]);
    customExpect(isFactoryWhitelisted, true, log + ", function: mapMechFactories()");
    isFactoryWhitelisted = await mechMarketplaceProxy.mapMechFactories(globalsInstance["mechFactoryNvmSubscriptionNativeAddress"]);
    customExpect(isFactoryWhitelisted, true, log + ", function: mapMechFactories()");

    // Check whitelisted balance trackers
    // FixedPriceNative
    let paymentType = "0xba699a34be8fe0e7725e93dcbce1701b0211a8ca61330aaeb8a05bf2ec7abed1";
    let balanceTracker = await mechMarketplaceProxy.mapPaymentTypeBalanceTrackers(paymentType);
    customExpect(balanceTracker, globalsInstance["balanceTrackerFixedPriceNativeAddress"], log + ", function: mapPaymentTypeBalanceTrackers()");
    // FixedPriceToken
    paymentType = "0x3679d66ef546e66ce9057c4a052f317b135bc8e8c509638f7966edfd4fcf45e9";
    balanceTracker = await mechMarketplaceProxy.mapPaymentTypeBalanceTrackers(paymentType);
    customExpect(balanceTracker, globalsInstance["balanceTrackerFixedPriceTokenAddress"], log + ", function: mapPaymentTypeBalanceTrackers()");
    // NvmSubscriptionNative
    paymentType = "0x803dd08fe79d91027fc9024e254a0942372b92f3ccabc1bd19f4a5c2b251c316";
    balanceTracker = await mechMarketplaceProxy.mapPaymentTypeBalanceTrackers(paymentType);
    customExpect(balanceTracker, globalsInstance["balanceTrackerNvmSubscriptionNativeAddress"], log + ", function: mapPaymentTypeBalanceTrackers()");
}

// Check BalanceTracker: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkBalanceTracker(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Get the contract instance
    const balanceTracker = await findContractInstance(provider, configContracts, contractName);
    // Check if the contract exists, since different networks might have different set of balance trackers
    if (typeof balanceTracker === "undefined") {
        return;
    }

    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    log += ", address: " + balanceTracker.address;
    // Check mech marketplace
    const mechMarketplace = await balanceTracker.mechMarketplace();
    customExpect(mechMarketplace, globalsInstance["mechMarketplaceProxyAddress"], log + ", function: mechMarketplace()");

    // Check drainer
    const drainer = await balanceTracker.drainer();
    customExpect(drainer, globalsInstance["drainerAddress"], log + ", function: drainer()");

    // Additionally check fixed native token
    if (contractName === "BalanceTrackerFixedPriceNative") {
        const wrappedNativeToken = await balanceTracker.wrappedNativeToken();
        customExpect(wrappedNativeToken, globalsInstance["wrappedNativeTokenAddress"], log + ", function: wrappedNativeToken()");
    }

    // Additionally check fixed token
    if (contractName === "BalanceTrackerFixedPriceToken") {
        const token = await balanceTracker.token();
        customExpect(token, globalsInstance["olasAddress"], log + ", function: token()");
    }

    // Additionally check NVM subscription for native
    if (contractName === "BalanceTrackerNvmSubscriptionNative") {
        const subscriptionNFT = await balanceTracker.subscriptionNFT();
        customExpect(subscriptionNFT, globalsInstance["subscriptionNFTAddress"], log + ", function: subscriptionNFT()");

        // Check if subscription exists
        if (globalsInstance["subscriptionTokenId"] !== "") {
            const subscriptionTokenId = await balanceTracker.subscriptionTokenId();
            customExpect(subscriptionTokenId.toString(), ethers.BigNumber.from(globalsInstance["subscriptionTokenId"]).toString(), log + ", function: subscriptionTokenId()");

            const tokenCreditRatio = await balanceTracker.tokenCreditRatio();
            customExpect(tokenCreditRatio.toString(), ethers.BigNumber.from(globalsInstance["tokenCreditRatio"]).toString(), log + ", function: tokenCreditRatio()");
        }
    }

    // Additionally check NVM subscription for tokens
    if (contractName === "BalanceTrackerNvmSubscriptionToken") {
        const subscriptionNFT = await balanceTracker.subscriptionNFT();
        customExpect(subscriptionNFT, globalsInstance["subscriptionNFTAddress"], log + ", function: subscriptionNFT()");

        // Different possible tokens
        if (typeof globalsInstance["subscriptionTokenIdUSDC"] !== "undefined") {
            const subscriptionTokenId = await balanceTracker.subscriptionTokenId();
            customExpect(subscriptionTokenId.toString(), ethers.BigNumber.from(globalsInstance["subscriptionTokenIdUSDC"]).toString(), log + ", function: subscriptionTokenIdUSDC()");

            const tokenCreditRatio = await balanceTracker.tokenCreditRatio();
            customExpect(tokenCreditRatio.toString(), ethers.BigNumber.from(globalsInstance["tokenCreditRatio"]).toString(), log + ", function: tokenCreditRatio()");
        }
    }
}

async function main() {
    // Read configuration from the JSON file
    const configFile = "docs/configuration.json";
    const dataFromJSON = fs.readFileSync(configFile, "utf8");
    const configs = JSON.parse(dataFromJSON);

    let numChains = configs.length;
    // ################################# VERIFY CONTRACTS WITH REPO #################################
    if (verifyRepo) {
        // Traverse all chains
        for (let i = 0; i < numChains; i++) {
            console.log("\n\nNetwork:", configs[i]["name"]);
            const contracts = configs[i]["contracts"];
            const chainId = configs[i]["chainId"];
            console.log("chainId", chainId);

            // Verify contracts
            for (let j = 0; j < contracts.length; j++) {
                console.log("Checking " + contracts[j]["name"]);
                const execSync = require("child_process").execSync;
                try {
                    execSync("scripts/audit_chains/audit_repo_contract.sh " + chainId + " " + contracts[j]["name"] + " " + contracts[j]["address"]);
                } catch (err) {
                    err.stderr.toString();
                }
            }
        }
    }
    // ################################# /VERIFY CONTRACTS WITH REPO #################################

    // ################################# VERIFY CONTRACTS SETUP #################################
    if (verifySetup) {
        const globalNames = {
            "gnosis": "scripts/deployment/globals_gnosis_mainnet.json",
            "base": "scripts/deployment/globals_base_mainnet.json",
            "polygon": "scripts/deployment/globals_polygon_mainnet.json",
            "optimism": "scripts/deployment/globals_optimism_mainnet.json"
        };

        const providerLinks = {
            "gnosis": "https://rpc.gnosischain.com",
            "base": "https://mainnet.base.org",
            "polygon": "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MATIC,
            "optimism": "https://public-op-mainnet.fastnode.io"
        };

        // Get all the globals processed
        const globals = new Array();
        const providers = new Array();
        numChains = Object.keys(globalNames).length;
        for (let i = 0; i < numChains; i++) {
            const dataJSON = fs.readFileSync(globalNames[configs[i]["name"]], "utf8");
            globals.push(JSON.parse(dataJSON));
            const provider = new ethers.providers.JsonRpcProvider(providerLinks[configs[i]["name"]]);
            providers.push(provider);
        }

        console.log("\nVerifying deployed contracts setup... If no error is output, then the contracts are correct.");

        // L2 contracts
        for (let i = 0; i < numChains; i++) {
            console.log("\n######## Verifying setup on CHAIN ID", configs[i]["chainId"]);

            const initLog = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"];

            let log = initLog + ", contract: " + "KarmaProxy";
            await checkKarmaProxy(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "KarmaProxy", log);

            log = initLog + ", contract: " + "MechMarketplaceProxy";
            await checkMechMarketplaceProxy(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "MechMarketplaceProxy", log);

            log = initLog + ", contract: " + "BalanceTrackerFixedPriceNative";
            await checkBalanceTracker(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "BalanceTrackerFixedPriceNative", log);

            log = initLog + ", contract: " + "BalanceTrackerFixedPriceToken";
            await checkBalanceTracker(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "BalanceTrackerFixedPriceToken", log);

            // Skip networks where not deployed
            if (i < 2) {
                log = initLog + ", contract: " + "BalanceTrackerNvmSubscriptionNative";
                await checkBalanceTracker(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "BalanceTrackerNvmSubscriptionNative", log);

                log = initLog + ", contract: " + "BalanceTrackerNvmSubscriptionToken";
                await checkBalanceTracker(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "BalanceTrackerNvmSubscriptionToken", log);
            }
        }
    }
    // ################################# /VERIFY CONTRACTS SETUP #################################
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });