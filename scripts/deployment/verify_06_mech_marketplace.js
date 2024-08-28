const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const stakingFactoryAddress = parsedData.stakingFactoryAddress;
const karmaProxyAddress = parsedData.karmaProxyAddress;
const minResponseTimeout = parsedData.minResponseTimeout;
const maxResponseTimeout = parsedData.maxResponseTimeout;

module.exports = [
    stakingFactoryAddress,
    karmaProxyAddress,
    minResponseTimeout,
    maxResponseTimeout
];