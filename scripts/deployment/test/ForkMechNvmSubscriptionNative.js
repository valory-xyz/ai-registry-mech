/* global process */
const { expect } = require("chai");
const { ethers } = require("hardhat");

// This works on a fork only!
const main = async () => {
    const fs = require("fs");
    const globalsFile = "globals.json";
    let dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    const maxDeliveryRate = 10;
    const data = "0x00";
    const minResponseTimeout = parsedData.minResponseTimeout;
    const mechServiceId = 99;
    const requesterServiceId = 0;

    const signers = await ethers.getSigners();
    const deployer = signers[0];
    console.log("Deployer:", deployer.address);

    // Service Registry
    const serviceRegistry = await ethers.getContractAt("MockServiceRegistry", parsedData.serviceRegistryAddress);

    // Mech Marketplace
    const mechMarketplace = await ethers.getContractAt("MechMarketplace", parsedData.mechMarketplaceProxyAddress);

    // Pseudo-create a service
    //await serviceRegistry.setServiceOwner(mechServiceId, deployer.address);

    // Create default priority mech
    //let tx = await mechMarketplace.create(mechServiceId, parsedData.mockMechFactoryAddress, mechCreationData);
    //let res = await tx.wait();
    // Get mech contract address from the event
    //const priorityMechAddress = "0x" + res.logs[0].topics[1].slice(26);
    const priorityMechAddress = parsedData.priorityMechAddress;
    // Get mech contract instance
    const priorityMech = await ethers.getContractAt("MockMech", priorityMechAddress);
    console.log("priorityMechAddress", priorityMechAddress);

    // Create default delivery mech
    //const deliveryServiceId = await priorityMech.serviceId();
    //await serviceRegistry.setServiceOwner(deliveryServiceId, deployer.address);
    //tx = await mechMarketplace.create(deliveryServiceId, parsedData.mockMechFactoryAddress, mechCreationData);
    //res = await tx.wait();
    //const deliveryMechAddress = "0x" + res.logs[0].topics[1].slice(26);
    //const deliveryMechAddress = parsedData.deliveryMechAddress;
    //const deliveryMech = await ethers.getContractAt("MockMech", deliveryMechAddress);
    //console.log("deliveryMechAddress", deliveryMechAddress);

    // Buy back burner are not relevant for now
    const balanceTrackerNvmSubscriptionNative = await ethers.getContractAt("BalanceTrackerNvmSubscriptionNative",
        parsedData.balanceTrackerNvmSubscriptionNativeAddress);

    // Get request Id
    const nonce = await mechMarketplace.mapNonces(deployer.address);
    let requestId = await mechMarketplace.getRequestId(deployer.address, data, nonce);
    console.log("requestId", requestId);

    // Get requester balance
    const subscription = await ethers.getContractAt("MockNvmSubscriptionNative", parsedData.subscriptionNFTAddress);
    const subscriptionBalance = await subscription.balanceOf("0x5bA93c8719338D4605767C23812e7f144d3644B1", parsedData.subscriptionTokenId);
    console.log("subscriptionBalance", subscriptionBalance);

    // Post a request
    await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x");
    // NOTE!!! Perform all the on-chain actions one by one, as RPC keeps delaying requests and failing

    //requestId = "0xe1f6a3affbe1992413d5729080a58d75bcadc3e1bda808c60ae58cc0d27db73e";
    //const requestInfo = await mechMarketplace.mapRequestIdInfos(requestId);
    //console.log(requestInfo);

    // Get the request status (requested priority)
    //let status = await mechMarketplace.getRequestStatus(requestId);
    //expect(status).to.equal(1);

    // Wait for delivery mech to engage
    //await new Promise(r => setTimeout(r, (minResponseTimeout + 1) * 1000));

    const deliverData = ethers.utils.defaultAbiCoder.encode(["uint256", "bytes"], [maxDeliveryRate, data]);

    // Deliver a request
    const mechDeliveryRate = await priorityMech.maxDeliveryRate();
    //await priorityMech.deliverMarketplace([requestId], [mechDeliveryRate], [deliverData]);

    // Check priority mech balance now
    let mechBalance = await balanceTrackerNvmSubscriptionNative.mapMechBalances(priorityMech.address);
    console.log("priorityMech balance:", mechBalance);
    //expect(mechBalance).to.equal(0);
    //mechBalance = await balanceTrackerNvmSubscriptionNative.mapMechBalances(priorityMech.address);
    //onsole.log("deliveryMech balance:", mechBalance);
    //expect(mechBalance).to.equal(2 * mechDeliveryRate);

    // Check requester leftover balance (note credit system for subscription)
    let balanceBefore = await balanceTrackerNvmSubscriptionNative.mapRequesterBalances(deployer.address);
    console.log(balanceBefore);
    //await balanceTrackerNvmSubscriptionNative.redeemRequesterCredits(deployer.address);
    let balanceAfter = await balanceTrackerNvmSubscriptionNative.mapRequesterBalances(deployer.address);
    console.log(balanceAfter);
    let balanceDiff = balanceBefore.sub(balanceAfter);
    console.log(balanceDiff);
    //expect(balanceDiff).to.equal(mechDeliveryRate);

    // Process payment for mech
    //await balanceTrackerNvmSubscriptionNative.processPaymentByMultisig(priorityMech.address);
    balanceAfter = await ethers.provider.getBalance(priorityMech.address);
    console.log("delivery mech native balance:", balanceAfter);

    // Drain funds to a buy back burner mock
    //await balanceTrackerNvmSubscriptionNative.drain();
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
