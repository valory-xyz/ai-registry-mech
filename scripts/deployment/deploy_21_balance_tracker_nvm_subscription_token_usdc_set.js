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
    const balanceTrackerNvmSubscriptionTokenUSDCAddress = parsedData.balanceTrackerNvmSubscriptionTokenUSDCAddress;
    const subscriptionNFTAddress = parsedData.subscriptionNFTAddress;
    const subscriptionTokenIdUSDC = parsedData.subscriptionTokenIdUSDC;
    const tokenCreditRatio = parsedData.tokenCreditRatio;

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

    // Get the contract instance
    const balanceTrackerNvmSubscription = await ethers.getContractAt("BalanceTrackerNvmSubscriptionToken", balanceTrackerNvmSubscriptionTokenUSDCAddress);

    // Transaction signing and execution
    console.log("21. EOA to set Balance trackers NVM subscription Token");
    console.log("You are signing the following transaction: BalanceTrackerNvmSubscriptionToken.connect(EOA).setSubscription()");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const result = await balanceTrackerNvmSubscription.connect(EOA).setSubscription(subscriptionNFTAddress,
        subscriptionTokenIdUSDC, tokenCreditRatio, { gasPrice });

    // Transaction details
    console.log("Contract deployment: BalanceTrackerNvmSubscriptionToken");
    console.log("Contract address:", balanceTrackerNvmSubscription.address);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
