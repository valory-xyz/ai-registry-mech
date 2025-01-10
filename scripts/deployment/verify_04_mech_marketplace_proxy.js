const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const mechMarketplaceAddress = parsedData.mechMarketplaceAddress;
const fee = parsedData.fee;
const minResponseTimeout = parsedData.minResponseTimeout;
const maxResponseTimeout = parsedData.maxResponseTimeout;
const iface = new ethers.utils.Interface(["function initialize(uint256,uint256,uint256)"]);
const proxyPayload = iface.encodeFunctionData("initialize", [fee, minResponseTimeout, maxResponseTimeout]);

module.exports = [
    mechMarketplaceAddress,
    proxyPayload
];