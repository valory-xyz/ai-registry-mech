/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("MechFixedPriceToken", function () {
    let priorityMechAddress;
    let priorityMech;
    let deliveryMechAddress;
    let deliveryMech;
    let serviceRegistry;
    let mechMarketplace;
    let token;
    let karma;
    let mechFactoryFixedPrice;
    let balanceTrackerFixedPriceToken;
    let signers;
    let deployer;
    const initMint = "1" + "0".repeat(25);
    const maxDeliveryRate = 1000;
    const data = "0x00";
    const fee = 10;
    const minResponseTimeout = 10;
    const maxResponseTimeout = 20;
    const mechServiceId = 1;
    const requesterServiceId = 0;
    const mechCreationData = ethers.utils.defaultAbiCoder.encode(["uint256"], [maxDeliveryRate]);

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const Token = await ethers.getContractFactory("ERC20Token");
        token = await Token.deploy();
        await token.deployed();

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

        // Wrapped native token and buy back burner are not relevant for now
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
        const MechFactoryFixedPrice = await ethers.getContractFactory("MechFactoryFixedPriceToken");
        mechFactoryFixedPrice = await MechFactoryFixedPrice.deploy(mechMarketplace.address);
        await mechFactoryFixedPrice.deployed();

        // Whitelist mech factory
        await mechMarketplace.setMechFactoryStatuses([mechFactoryFixedPrice.address], [true]);

        // Whitelist marketplace in the karma proxy
        await karma.setMechMarketplaceStatuses([mechMarketplace.address], [true]);

        // Pseudo-create two services
        await serviceRegistry.setServiceOwner(mechServiceId, deployer.address);
        await serviceRegistry.setServiceOwner(mechServiceId + 1, deployer.address);

        // Pseudo-create a requester service
        await serviceRegistry.setServiceOwner(requesterServiceId + 3, signers[1].address);

        // Create default priority mech
        let tx = await mechMarketplace.create(mechServiceId, mechFactoryFixedPrice.address, mechCreationData);
        let res = await tx.wait();
        // Get mech contract address from the event
        priorityMechAddress = "0x" + res.logs[0].topics[1].slice(26);
        // Get mech contract instance
        priorityMech = await ethers.getContractAt("MechFixedPriceToken", priorityMechAddress);

        // Create default delivery mech
        tx = await mechMarketplace.create(mechServiceId + 1, mechFactoryFixedPrice.address, mechCreationData);
        res = await tx.wait();
        // Get mech contract address from the event
        deliveryMechAddress = "0x" + res.logs[0].topics[1].slice(26);
        // Get mech contract instance
        deliveryMech = await ethers.getContractAt("MechFixedPriceToken", deliveryMechAddress);

        // Deploy
        const BalanceTrackerFixedPriceToken = await ethers.getContractFactory("BalanceTrackerFixedPriceToken");
        balanceTrackerFixedPriceToken = await BalanceTrackerFixedPriceToken.deploy(mechMarketplace.address,
            deployer.address, token.address);
        await balanceTrackerFixedPriceToken.deployed();

        // Whitelist balance tracker
        const paymentTypeHash = await priorityMech.paymentType();
        await mechMarketplace.setPaymentTypeBalanceTrackers([paymentTypeHash], [balanceTrackerFixedPriceToken.address]);

        // Mint tokens
        await token.mint(deployer.address, initMint);
    });

    context("Deliver", async function () {
        it("Delivering request by a priority mech", async function () {
            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Try to create a request without any tokens approved
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x")
            ).to.be.reverted;
            
            // Approve tokens to post a request
            await token.approve(balanceTrackerFixedPriceToken.address, maxDeliveryRate);
            
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x");

            // Get the request status (requested priority)
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            // Deliver a request
            await priorityMech.deliverToMarketplace([requestId], [data]);

            // Get the request status (delivered)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(3);

            // Try to deliver the same request again
            await priorityMech.deliverToMarketplace([requestId], [data]);

            // Check mech karma
            let mechKarma = await karma.mapMechKarma(priorityMech.address);
            expect(mechKarma).to.equal(1);
            // Check requester mech karma
            mechKarma = await karma.mapRequesterMechKarma(deployer.address, priorityMech.address);
            expect(mechKarma).to.equal(1);
        });

        it("Delivering request by a priority mech with pre-paid logic", async function () {
            // Get request Id
            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Approve tokens to post a request
            await token.approve(balanceTrackerFixedPriceToken.address, maxDeliveryRate - 1);

            // Pre-pay the contract insufficient amount for posting a request
            await balanceTrackerFixedPriceToken.deposit(maxDeliveryRate - 1);

            // Try to create request with insufficient pre-paid amount
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x")
            ).to.be.reverted;

            // Approve more tokens
            await token.approve(balanceTrackerFixedPriceToken.address, maxDeliveryRate);

            // Pre-pay the contract more for posting a request
            await balanceTrackerFixedPriceToken.deposit(maxDeliveryRate);

            // Post a request
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x");

            // Get the request status (requested priority)
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            // Deliver a request
            await priorityMech.deliverToMarketplace([requestId], [data]);

            // Get the request status (delivered)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(3);

            // Try to deliver the same request again
            await priorityMech.deliverToMarketplace([requestId], [data]);

            // Check mech karma
            let mechKarma = await karma.mapMechKarma(priorityMech.address);
            expect(mechKarma).to.equal(1);
            // Check requester mech karma
            mechKarma = await karma.mapRequesterMechKarma(deployer.address, priorityMech.address);
            expect(mechKarma).to.equal(1);

            // Check priority mech balance now
            let mechBalance = await balanceTrackerFixedPriceToken.mapMechBalances(priorityMech.address);
            expect(mechBalance).to.equal(maxDeliveryRate);

            const balanceBefore = await token.balanceOf(priorityMech.address);
            // Process payment for mech
            await balanceTrackerFixedPriceToken.processPaymentByMultisig(priorityMech.address);
            const balanceAfter = await token.balanceOf(priorityMech.address);

            // Check charged fee
            let collectedFees = await balanceTrackerFixedPriceToken.collectedFees();
            // Since the delivery rate is smaller than MAX_FEE_FACTOR, the minimal fee was charged
            expect(collectedFees).to.equal(1);

            // Drain funds to a buy back burner mock
            await balanceTrackerFixedPriceToken.drain();
            collectedFees = await balanceTrackerFixedPriceToken.collectedFees();
            expect(collectedFees).to.equal(0);

            // Check mech payout: payment - fee
            const balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(maxDeliveryRate - 1);

            // Check requester leftover balance
            let requesterBalance = await balanceTrackerFixedPriceToken.mapRequesterBalances(deployer.address);
            expect(requesterBalance).to.equal(maxDeliveryRate - 1);
        });

        it("Delivering request by a different mech", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Approve tokens to post a request
            await token.approve(balanceTrackerFixedPriceToken.address, maxDeliveryRate);

            // Create a request
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x");

            // Try to deliver by a delivery mech right away
            await expect(
                deliveryMech.deliverToMarketplace([requestId], [data])
            ).to.be.revertedWithCustomError(mechMarketplace, "PriorityMechResponseTimeout");

            // Get the request status (requested priority)
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            // Increase the time such that the request expires for a priority mech
            await helpers.time.increase(maxResponseTimeout);

            // Get the request status (requested expired)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(2);

            // Try to deliver by a mech with bigger max Delivery rate
            await deliveryMech.changeMaxDeliveryRate(maxDeliveryRate + 1);
            await expect(
                deliveryMech.deliverToMarketplace([requestId], [data])
            ).to.be.revertedWithCustomError(mechMarketplace, "Overflow");

            // Change max delivery rate back
            await deliveryMech.changeMaxDeliveryRate(maxDeliveryRate);

            // Deliver a request by the delivery mech
            await deliveryMech.deliverToMarketplace([requestId], [data]);

            // Try to deliver the same request again (gets empty data)
            await deliveryMech.deliverToMarketplace([requestId], [data]);

            // Get the request status (delivered)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(3);

            // Check priority mech and delivery mech karma
            let mechKarma = await karma.mapMechKarma(priorityMech.address);
            expect(mechKarma).to.equal(-1);
            mechKarma = await karma.mapMechKarma(deliveryMech.address);
            expect(mechKarma).to.equal(1);

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });
});
