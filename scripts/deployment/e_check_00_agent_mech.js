/*global process*/

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const providerName = parsedData.providerName;
    const agentType = parsedData.agentType;
    let agentMechAddress;
    if (agentType === "subscription") {
        agentMechAddress = parsedData.agentMechSubscriptionAddress;
    } else {
        agentMechAddress = parsedData.agentMechAddress;
    }

    // Contract verification
    const execSync = require("child_process").execSync;
    execSync("npx hardhat verify --constructor-args scripts/deployment/verify_00_agent_mech.js --network " + providerName + " " + agentMechAddress, { encoding: "utf-8" });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

