/*global process, hre*/

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    const provider = new hre.ethers.providers.JsonRpcProvider(parsedData.networkURL);
    const signers = await hre.ethers.getSigners();

    const deployer = signers[0];
    console.log("Deployer is:", deployer.address);

    const mechAddress = "";
    const mech = await hre.ethers.getContractAt("MechFixedPriceNative", mechAddress);
    const mechMarketplaceAddress = await mech.mechMarketplace();
    const serviceRegistryAddress = await mech.serviceRegistry();
    const serviceId = await mech.tokenId();
    const maxDeliveryRate = await mech.maxDeliveryRate();
    await hre.run("verify:verify", {
        address: mechAddress,
        constructorArguments: [mechMarketplaceAddress, serviceRegistryAddress, serviceId, maxDeliveryRate],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

