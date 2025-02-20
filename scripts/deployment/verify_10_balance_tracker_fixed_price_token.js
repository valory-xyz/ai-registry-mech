const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const mechMarketplaceProxyAddress = parsedData.mechMarketplaceProxyAddress;
const drainerAddress = parsedData.drainerAddress;
const olasAddress = parsedData.olasAddress;

module.exports = [
    mechMarketplaceProxyAddress,
    drainerAddress,
    olasAddress
];