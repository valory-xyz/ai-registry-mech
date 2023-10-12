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
    const agentId = parsedData.agentId;
    const price = ethers.BigNumber.from(parsedData.price);
    let EOA;

    let networkURL;
    if (providerName === "gnosis") {
        if (!process.env.GNOSISSCAN_API_KEY) {
            console.log("set GNOSISSCAN_API_KEY env variable");
            return;
        }
        networkURL = "https://rpc.gnosischain.com";
    } else if (providerName === "chiado") {
        networkURL = "https://rpc.chiadochain.net";
    } else {
        console.log("Unknown network provider", providerName);
        return;
    }

    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    const signers = await ethers.getSigners();

    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Transaction signing and execution
    console.log("4. EOA to deploy AgentMech pointed to AgentRegistry, agentId and price");
    const AgentMech = await ethers.getContractFactory("AgentMech");
    console.log("You are signing the following transaction: AgentMech.connect(EOA).deploy(agentRegistryAddress, agentId, price)");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const agentMech = await AgentMech.connect(EOA).deploy(agentRegistryAddress, agentId, price, { gasPrice });
    const result = await agentMech.deployed();

    // Transaction details
    console.log("Contract deployment: AgentMech");
    console.log("Contract address:", agentMech.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.agentMechAddress = agentMech.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_04_agent_mech.js --network " + providerName + " " + agentMech.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
