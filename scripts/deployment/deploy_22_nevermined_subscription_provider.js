/*global hre, process*/

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
    const subscriptionTokenId = parsedData.subscriptionTokenId;
    const subscriptionNFTAddress = parsedData.subscriptionNFTAddress;
    const didRegistryAddress = parsedData.didRegistryAddress;
    const transferNFTConditionAddress = parsedData.transferNFTConditionAddress;
    const escrowPaymentConditionAddress = parsedData.escrowPaymentConditionAddress;

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
    console.log("22. EOA to deploy Subscription Provider");
    console.log("You are signing the following transaction: SubscriptionProvider.connect(EOA).deploy()");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const SubscriptionProvider = await ethers.getContractFactory("SubscriptionProvider");
    const subscriptionProvider = await SubscriptionProvider.connect(EOA).deploy(subscriptionTokenId,
        subscriptionNFTAddress, didRegistryAddress, transferNFTConditionAddress, escrowPaymentConditionAddress, { gasPrice });
    // In case when gas calculation is not working correctly on Arbitrum
    //const gasLimit = 60000000;
    const result = await subscriptionProvider.deployed();

    // Transaction details
    console.log("Contract deployment: SubscriptionProvider");
    console.log("Contract address:", subscriptionProvider.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.subscriptionProviderAddress = subscriptionProvider.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        await hre.run("verify:verify", {
            address: subscriptionProvider.address,
            constructorArguments: [subscriptionTokenId, subscriptionNFTAddress, didRegistryAddress, transferNFTConditionAddress, escrowPaymentConditionAddress]
        });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
