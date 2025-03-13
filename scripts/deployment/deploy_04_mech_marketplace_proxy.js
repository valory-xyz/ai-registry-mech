/*global process, hre*/

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
    const mechMarketplaceAddress = parsedData.mechMarketplaceAddress;
    const fee = parsedData.fee;
    const minResponseTimeout = parsedData.minResponseTimeout;
    const maxResponseTimeout = parsedData.maxResponseTimeout;

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

    // Assemble the mech marketplace proxy data
    const mechMarketplace = await ethers.getContractAt("MechMarketplace", mechMarketplaceAddress);
    const proxyPayload = mechMarketplace.interface.encodeFunctionData("initialize", [fee, minResponseTimeout, maxResponseTimeout]);

    // Transaction signing and execution
    console.log("4. EOA to deploy Mech Marketplace Proxy");
    console.log("You are signing the following transaction: MechMarketplaceProxy.connect(EOA).deploy()");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const MechMarketplaceProxy = await ethers.getContractFactory("MechMarketplaceProxy");
    const mechMarketplaceProxy = await MechMarketplaceProxy.connect(EOA).deploy(mechMarketplaceAddress, proxyPayload,
        { gasPrice });
    // In case when gas calculation is not working correctly on Arbitrum
    //const gasLimit = 60000000;
    const result = await mechMarketplaceProxy.deployed();

    // Transaction details
    console.log("Contract deployment: MechMarketplaceProxy");
    console.log("Contract address:", mechMarketplaceProxy.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.mechMarketplaceProxyAddress = mechMarketplaceProxy.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        await hre.run("verify:verify", {
            address: mechMarketplaceProxy.address,
            constructorArguments: [mechMarketplaceAddress, proxyPayload]
        });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
