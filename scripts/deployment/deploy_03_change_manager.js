/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const useLedger = parsedData.useLedger;
    const derivationPath = parsedData.derivationPath;
    const providerName = parsedData.providerName;
    const agentRegistryAddress = parsedData.agentRegistryAddress;
    const agentType = parsedData.agentType;
    let agentFactoryAddress;
    if (agentType === "subscription") {
        agentFactoryAddress = parsedData.agentFactorySubscriptionAddress;
    } else {
        agentFactoryAddress = parsedData.agentFactoryAddress;
    }

    let networkURL = parsedData.networkURL;
    if (providerName === "polygon") {
        if (!process.env.ALCHEMY_API_KEY_MATIC) {
            console.log("set ALCHEMY_API_KEY_MATIC env variable");
        }
        networkURL += process.env.ALCHEMY_API_KEY_MATIC;
    } else if (providerName === "polygonMumbai") {
        if (!process.env.ALCHEMY_API_KEY_MUMBAI) {
            console.log("set ALCHEMY_API_KEY_MUMBAI env variable");
            return;
        }
        networkURL += process.env.ALCHEMY_API_KEY_MUMBAI;
    }

    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    const signers = await ethers.getSigners();

    let EOA;
    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the contracts
    const agentRegistry = await ethers.getContractAt("AgentRegistry", agentRegistryAddress);

    // Transaction signing and execution
    // 3. EOA to change the manager of AgentRegistry via `changeManager(AgentRegistry)`;
    console.log("You are signing the following transaction: agentRegistry.connect(EOA).changeManager()");
    let result = await agentRegistry.connect(EOA).changeManager(agentFactoryAddress);
    // Transaction details
    console.log("Contract deployment: AgentRegistry");
    console.log("Contract address:", agentRegistryAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
