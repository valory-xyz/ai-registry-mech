/* global process */
const { expect } = require("chai");
const { ethers } = require("hardhat");

// This works on a fork only!
const main = async () => {
    const fs = require("fs");
    const globalsFile = "globals.json";
    let dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    const signers = await ethers.getSigners();
    const deployer = signers[0];
    console.log("Deployer:", deployer.address);

    // Get requester balances
    const accounts = ["", ""];
    const subscription = await ethers.getContractAt("MockNvmSubscriptionNative", parsedData.subscriptionNFTAddress);
    for (let i = 0; i < accounts.length; i++) {
        const subscriptionBalance = await subscription.balanceOf(accounts[i], parsedData.subscriptionTokenId);
        console.log("account:", accounts[i]);
        console.log("subscriptionBalance:", subscriptionBalance);
        //await subscription.safeTransferFrom(deployer.address, accounts[i], parsedData.subscriptionTokenId, amounts[i], "0x");
    }
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
