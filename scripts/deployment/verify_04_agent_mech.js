const { ethers } = require("hardhat");
const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const agentType = parsedData.agentType;

if (agentType === "subscription") {
    module.exports = [
        parsedData.agentRegistryAddress,
        parsedData.agentIdSubscription,
        parsedData.minCreditsPerRequest,
        parsedData.subscriptionNFTAddress,
        parsedData.subscriptionTokenId
    ];
} else {
    module.exports = [
        parsedData.agentRegistryAddress,
        parsedData.agentId,
        parsedData.price
    ];
}