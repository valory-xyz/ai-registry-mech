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
    const gasPriceInGwei = parsedData.gasPriceInGwei;
    const agentRegistryAddress = parsedData.agentRegistryAddress;
    const agentType = parsedData.agentType;

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

    // Transaction signing and execution
    console.log("2. EOA to deploy AgentFactory pointed to AgentRegistry");
    let AgentFactory;
    if (agentType === "subscription") {
        AgentFactory = await ethers.getContractFactory("AgentFactorySubscription");
    } else {
        AgentFactory = await ethers.getContractFactory("AgentFactory");
    }
    console.log("You are signing the following transaction: AgentFactory.connect(EOA).deploy()");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const agentFactory = await AgentFactory.connect(EOA).deploy(agentRegistryAddress, { gasPrice });
    // In case when gas calculation is not working correctly on Arbitrum
    //const gasLimit = 60000000;
    //const agentFactory = await AgentFactory.connect(EOA).deploy(agentRegistryAddress, { gasLimit });
    const result = await agentFactory.deployed();

    // Transaction details
    console.log("Contract deployment: AgentFactory");
    console.log("Contract address:", agentFactory.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    if (agentType === "subscription") {
        parsedData.agentFactorySubscriptionAddress = agentFactory.address;
    } else {
        parsedData.agentFactoryAddress = agentFactory.address;
    }
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_02_agent_factory.js --network " + providerName + " " + agentFactory.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
