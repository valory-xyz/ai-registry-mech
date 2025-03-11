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
    const mechMarketplaceProxyAddress = parsedData.mechMarketplaceProxyAddress;
    const balanceTrackerNvmSubscriptionTokenAddress = parsedData.balanceTrackerNvmSubscriptionTokenAddress;

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
    const mechMarketplace = await ethers.getContractAt("MechMarketplace", mechMarketplaceProxyAddress);

    // Transaction signing and execution
    console.log("20. EOA to set Balance tracker NVM subscription token USDC");
    console.log("You are signing the following transaction: MechMarketplaceProxy.connect(EOA).setPaymentTypeBalanceTrackers()");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const result = await mechMarketplace.connect(EOA).setPaymentTypeBalanceTrackers(
        ["0x0d6fd99afa9c4c580fab5e341922c2a5c4b61d880da60506193d7bf88944dd14"],
        [balanceTrackerNvmSubscriptionTokenAddress],
        { gasPrice }
    );

    // Transaction details
    console.log("Contract deployment: MechMarketplaceProxy");
    console.log("Contract address:", mechMarketplace.address);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
