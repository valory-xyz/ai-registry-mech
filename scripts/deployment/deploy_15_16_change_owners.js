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
    const karmaProxyAddress = parsedData.karmaProxyAddress;
    const mechMarketplaceProxyAddress = parsedData.mechMarketplaceProxyAddress;
    const bridgeMediatorAddress = parsedData.bridgeMediatorAddress;

    let networkURL = parsedData.networkURL;
    if (providerName === "polygon") {
        if (!process.env.ALCHEMY_API_KEY_MATIC) {
            console.log("set ALCHEMY_API_KEY_MATIC env variable");
        }
        networkURL += process.env.ALCHEMY_API_KEY_MATIC;
    } else if (providerName === "polygonAmoy") {
        if (!process.env.ALCHEMY_API_KEY_AMOY) {
            console.log("set ALCHEMY_API_KEY_AMOY env variable");
            return;
        }
        networkURL += process.env.ALCHEMY_API_KEY_AMOY;
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

    // Get the proxy contracts
    const karmaProxy = await ethers.getContractAt("Karma", karmaProxyAddress);
    const mechMarketplaceProxy = await ethers.getContractAt("MechMarketplace", mechMarketplaceProxyAddress);

    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");

    // Transaction signing and execution
    console.log("15. EOA to change owner in KarmaProxy");
    console.log("You are signing the following transaction: KarmaProxy.connect(EOA).changeOwner()");
    let result = await karmaProxy.connect(EOA).changeOwner(bridgeMediatorAddress, { gasPrice });

    // Transaction details
    console.log("Contract deployment: KarmaProxy");
    console.log("Contract address:", karmaProxy.address);
    console.log("Transaction:", result.hash);

    // Transaction signing and execution
    console.log("16. EOA to change owner in MechMarketplaceProxy");
    console.log("You are signing the following transaction: MechMarketplaceProxy.connect(EOA).changeOwner()");
    result = await mechMarketplaceProxy.connect(EOA).changeOwner(bridgeMediatorAddress, { gasPrice });

    // Transaction details
    console.log("Contract deployment: MechMarketplaceProxy");
    console.log("Contract address:", mechMarketplaceProxy.address);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
