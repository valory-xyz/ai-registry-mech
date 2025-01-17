const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const serviceRegistryAddress = parsedData.serviceRegistryAddress;
const karmaProxyAddress = parsedData.karmaProxyAddress;

module.exports = [
    serviceRegistryAddress,
    karmaProxyAddress
];