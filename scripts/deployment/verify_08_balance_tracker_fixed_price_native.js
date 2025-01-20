const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const mechMarketplaceProxyAddress = parsedData.mechMarketplaceProxyAddress;
const buyBackBurnerAddress = parsedData.buyBackBurnerAddress;
const wrappedNativeTokenAddress = parsedData.wrappedNativeTokenAddress;

module.exports = [
    mechMarketplaceProxyAddress,
    buyBackBurnerAddress,
    wrappedNativeTokenAddress
];