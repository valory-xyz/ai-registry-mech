/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MechNvmSubscriptionNative", function () {
    let priorityMechAddress;
    let priorityMech;
    let serviceRegistry;
    let mechMarketplace;
    let karma;
    let mechFactoryNvmSubscriptionNative;
    let balanceTrackerNvmSubscriptionNative;
    let mockNvmSubscriptionNative;
    let weth;
    let signers;
    let deployer;
    const maxDeliveryRate = 10;
    const data = "0x00";
    const fee = 100;
    const creditTokenRatio = 3;
    const subscriptionId = 1;
    const minResponseTimeout = 10;
    const maxResponseTimeout = 20;
    const mechServiceId = 1;
    const requesterServiceId = 0;
    const mechCreationData = ethers.utils.defaultAbiCoder.encode(["uint256"], [maxDeliveryRate]);

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        // Karma implementation and proxy
        const Karma = await ethers.getContractFactory("Karma");
        const karmaImplementation = await Karma.deploy();
        await karmaImplementation.deployed();

        // Initialize karma
        let proxyData = karmaImplementation.interface.encodeFunctionData("initialize", []);
        const KarmaProxy = await ethers.getContractFactory("KarmaProxy");
        const karmaProxy = await KarmaProxy.deploy(karmaImplementation.address, proxyData);
        await karmaProxy.deployed();

        karma = await ethers.getContractAt("Karma", karmaProxy.address);

        const ServiceRegistry = await ethers.getContractFactory("MockServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy();
        await serviceRegistry.deployed();

        // Mech Marketplace
        const MechMarketplace = await ethers.getContractFactory("MechMarketplace");
        mechMarketplace = await MechMarketplace.deploy(serviceRegistry.address, karma.address);
        await mechMarketplace.deployed();

        // Deploy and initialize marketplace proxy
        proxyData = MechMarketplace.interface.encodeFunctionData("initialize",
            [fee, minResponseTimeout, maxResponseTimeout]);
        const MechMarketplaceProxy = await ethers.getContractFactory("MechMarketplaceProxy");
        const mechMarketplaceProxy = await MechMarketplaceProxy.deploy(mechMarketplace.address, proxyData);
        await mechMarketplaceProxy.deployed();

        mechMarketplace = await ethers.getContractAt("MechMarketplace", mechMarketplaceProxy.address);

        // Deploy mech factory
        const MechFactoryNvmSubscriptionNative = await ethers.getContractFactory("MechFactoryNvmSubscriptionNative");
        mechFactoryNvmSubscriptionNative = await MechFactoryNvmSubscriptionNative.deploy(mechMarketplace.address);
        await mechFactoryNvmSubscriptionNative.deployed();

        // Whitelist mech factory
        await mechMarketplace.setMechFactoryStatuses([mechFactoryNvmSubscriptionNative.address], [true]);

        // Whitelist marketplace in the karma proxy
        await karma.setMechMarketplaceStatuses([mechMarketplace.address], [true]);

        // Pseudo-create two services
        await serviceRegistry.setServiceOwner(mechServiceId, deployer.address);
        await serviceRegistry.setServiceOwner(mechServiceId + 1, deployer.address);

        // Pseudo-create a requester service
        await serviceRegistry.setServiceOwner(requesterServiceId + 3, signers[1].address);

        // Create default priority mech
        let tx = await mechMarketplace.create(mechServiceId, mechFactoryNvmSubscriptionNative.address, mechCreationData);
        let res = await tx.wait();
        // Get mech contract address from the event
        priorityMechAddress = "0x" + res.logs[0].topics[1].slice(26);
        // Get mech contract instance
        priorityMech = await ethers.getContractAt("MechNvmSubscriptionNative", priorityMechAddress);

        const WETH = await ethers.getContractFactory("WETH9");
        weth = await WETH.deploy();
        await weth.deployed();

        // Deploy balance tracker
        // Buy back burner are not relevant for now
        const BalanceTrackerNvmSubscriptionNative = await ethers.getContractFactory("BalanceTrackerNvmSubscriptionNative");
        balanceTrackerNvmSubscriptionNative = await BalanceTrackerNvmSubscriptionNative.deploy(mechMarketplace.address,
            deployer.address, weth.address, creditTokenRatio);
        await balanceTrackerNvmSubscriptionNative.deployed();

        // Deploy mock NVM subscription
        const MockNvmSubscriptionNative = await ethers.getContractFactory("MockNvmSubscriptionNative");
        mockNvmSubscriptionNative = await MockNvmSubscriptionNative.deploy(balanceTrackerNvmSubscriptionNative.address,
            creditTokenRatio);
        await mockNvmSubscriptionNative.deployed();

        // Set subscription contract address
        await balanceTrackerNvmSubscriptionNative.setSubscription(mockNvmSubscriptionNative.address, subscriptionId);

        // Whitelist balance tracker
        const paymentTypeHash = await priorityMech.paymentType();
        await mechMarketplace.setPaymentTypeBalanceTrackers([paymentTypeHash], [balanceTrackerNvmSubscriptionNative.address]);
    });

    context("Deliver", async function () {
        it("Delivering request by a priority mech", async function () {
            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Try to create a request without any subscription balance
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x")
            ).to.be.reverted;

            const numCredits = maxDeliveryRate * 10;

            // Buy subscription
            await mockNvmSubscriptionNative.mint(subscriptionId, numCredits, {value: numCredits * creditTokenRatio});

            // Post a request
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x");

            // Get the request status (requested priority)
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            const deliverData = ethers.utils.defaultAbiCoder.encode(["uint256", "bytes"], [maxDeliveryRate, data]);

            // Deliver a request
            await priorityMech.deliverToMarketplace([requestId], [deliverData]);

            // Get the request status (delivered)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(3);

            // Try to deliver the same request again
            await priorityMech.deliverToMarketplace([requestId], [deliverData]);

            // Check mech karma
            let mechKarma = await karma.mapMechKarma(priorityMech.address);
            expect(mechKarma).to.equal(1);
            // Check requester mech karma
            mechKarma = await karma.mapRequesterMechKarma(deployer.address, priorityMech.address);
            expect(mechKarma).to.equal(1);
        });

        it("Delivering request by a priority mech", async function () {
            // Get request Id
            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Buy insufficient subscription
            await mockNvmSubscriptionNative.mint(subscriptionId, maxDeliveryRate - 1,
                {value: (maxDeliveryRate - 1) * creditTokenRatio});

            // Try to create request with insufficient pre-paid amount
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x")
            ).to.be.revertedWithCustomError(balanceTrackerNvmSubscriptionNative, "InsufficientBalance");

            const numCredits = maxDeliveryRate * 10;

            // Buy more credits
            await mockNvmSubscriptionNative.mint(subscriptionId, numCredits, {value: numCredits * creditTokenRatio});

            // Post a request
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x");

            // Get the request status (requested priority)
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            const deliverData = ethers.utils.defaultAbiCoder.encode(["uint256", "bytes"], [maxDeliveryRate, data]);

            // Deliver a request
            await priorityMech.deliverToMarketplace([requestId], [deliverData]);

            // Check priority mech balance now
            let mechBalance = await balanceTrackerNvmSubscriptionNative.mapMechBalances(priorityMech.address);
            expect(mechBalance).to.equal(maxDeliveryRate);

            let balanceBefore = await ethers.provider.getBalance(priorityMech.address);
            // Process payment for mech
            await balanceTrackerNvmSubscriptionNative.processPaymentByMultisig(priorityMech.address);
            let balanceAfter = await ethers.provider.getBalance(priorityMech.address);

            // Check charged fee
            let collectedFees = await balanceTrackerNvmSubscriptionNative.collectedFees();
            // Since the delivery rate is smaller than MAX_FEE_FACTOR, the minimal fee was charged
            expect(collectedFees).to.equal(1);

            // Drain funds to a buy back burner mock
            await balanceTrackerNvmSubscriptionNative.drain();
            collectedFees = await balanceTrackerNvmSubscriptionNative.collectedFees();
            expect(collectedFees).to.equal(0);

            // Check mech payout: payment - fee
            let balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(maxDeliveryRate * creditTokenRatio - 1);

            let requesterBalance1155Before = await mockNvmSubscriptionNative.balanceOf(deployer.address, subscriptionId);

            // Check requester leftover balance (note credit system for subscription)
            balanceBefore = await balanceTrackerNvmSubscriptionNative.mapRequesterBalances(deployer.address);
            await balanceTrackerNvmSubscriptionNative.redeemRequesterCredits(deployer.address);
            balanceAfter = await balanceTrackerNvmSubscriptionNative.mapRequesterBalances(deployer.address);
            balanceDiff = balanceBefore.sub(balanceAfter);
            expect(balanceDiff).to.equal(maxDeliveryRate);

            let requesterBalance1155After = await mockNvmSubscriptionNative.balanceOf(deployer.address, subscriptionId);
            balanceDiff = requesterBalance1155Before.sub(requesterBalance1155After);
            expect(balanceDiff).to.equal(maxDeliveryRate);
        });
    });
});
