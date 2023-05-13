const { ethers } = require("hardhat");
const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const agentRegistryAddress = parsedData.agentRegistryAddress;
const agentId = parsedData.agentId;
const price = ethers.BigNumber.from(parsedData.price);

module.exports = [
    agentRegistryAddress,
    agentId,
    price
];