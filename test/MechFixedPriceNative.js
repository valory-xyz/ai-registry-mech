/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("MechFixedPriceNative", function () {
    let MechFixedPriceNative;
    let priorityMechAddress;
    let priorityMech;
    let deliveryMechAddress;
    let deliveryMech;
    let serviceRegistry;
    let mechMarketplace;
    let karma;
    let mechFactoryFixedPrice;
    let balanceTrackerFixedPriceNative;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
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

        MechFixedPriceNative = await ethers.getContractFactory("MechFixedPriceNative");

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
        const MechFactoryFixedPrice = await ethers.getContractFactory("MechFactoryFixedPriceNative");
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
        priorityMech = await ethers.getContractAt("MechFixedPriceNative", priorityMechAddress);

        // Create default delivery mech
        tx = await mechMarketplace.create(mechServiceId + 1, mechFactoryFixedPrice.address, mechCreationData);
        res = await tx.wait();
        // Get mech contract address from the event
        deliveryMechAddress = "0x" + res.logs[0].topics[1].slice(26);
        // Get mech contract instance
        deliveryMech = await ethers.getContractAt("MechFixedPriceNative", deliveryMechAddress);

        // Deploy
        const BalanceTrackerFixedPriceNative = await ethers.getContractFactory("BalanceTrackerFixedPriceNative");
        balanceTrackerFixedPriceNative = await BalanceTrackerFixedPriceNative.deploy(mechMarketplace.address,
            deployer.address, deployer.address);
        await balanceTrackerFixedPriceNative.deployed();

        // Whitelist balance tracker
        const paymentTypeHash = await priorityMech.paymentType();
        await mechMarketplace.setPaymentTypeBalanceTrackers([paymentTypeHash], [balanceTrackerFixedPriceNative.address]);
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            // Zero mech marketplace
            await expect(
                MechFixedPriceNative.deploy(AddressZero, AddressZero, 0, 0)
            ).to.be.revertedWithCustomError(MechFixedPriceNative, "ZeroAddress");

            // Zero service registry
            await expect(
                MechFixedPriceNative.deploy(mechMarketplace.address, AddressZero, 0, 0)
            ).to.be.revertedWithCustomError(MechFixedPriceNative, "ZeroAddress");

            // Zero service Id
            await expect(
                MechFixedPriceNative.deploy(mechMarketplace.address, serviceRegistry.address, 0, 0)
            ).to.be.revertedWithCustomError(MechFixedPriceNative, "ZeroValue");

            // Zero maxDeliveryRate
            await expect(
                MechFixedPriceNative.deploy(mechMarketplace.address, serviceRegistry.address, mechServiceId, 0)
            ).to.be.revertedWithCustomError(MechFixedPriceNative, "ZeroValue");

            // Service Id does not exist
            await expect(
                MechFixedPriceNative.deploy(mechMarketplace.address, serviceRegistry.address, mechServiceId + 10, maxDeliveryRate)
            ).to.be.reverted;
        });
    });

    context("Request", async function () {
        it("Creating an agent mech and doing a request", async function () {
            // Try to post a request directly to the mech
            await expect(
                priorityMech.requestFromMarketplace(deployer.address, data, 0)
            ).to.be.revertedWithCustomError(priorityMech, "MarketplaceNotAuthorized");

            // Response time is out of bounds
            await expect(
                mechMarketplace.request("0x", mechServiceId, requesterServiceId, 0, "0x")
            ).to.be.revertedWithCustomError(mechMarketplace, "OutOfBounds");

            // Try to request to a mech with an empty data
            await expect(
                mechMarketplace.request("0x", mechServiceId, requesterServiceId, minResponseTimeout, "0x")
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroValue");

            // Try to request to a zero service Id priority mech
            await expect(
                mechMarketplace.request(data, 0, requesterServiceId, minResponseTimeout, "0x")
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroAddress");

            // Try to request by a wrong requester service Id
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId + 3, minResponseTimeout, "0x")
            ).to.be.revertedWithCustomError(mechMarketplace, "OwnerOnly");

            // Response time is out of bounds
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout - 1, "0x")
            ).to.be.revertedWithCustomError(mechMarketplace, "OutOfBounds");
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId, maxResponseTimeout + 1, "0x")
            ).to.be.revertedWithCustomError(mechMarketplace, "OutOfBounds");

            // Change max response timeout close to type(uint32).max
            const closeToMaxUint32 = "4294967295";
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId, closeToMaxUint32, "0x")
            ).to.be.revertedWithCustomError(mechMarketplace, "Overflow");

            // Try to request to a mech with an incorrect mech service Id
            await expect(
                mechMarketplace.request(data, mechServiceId + 2, requesterServiceId, minResponseTimeout, "0x")
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroAddress");

            // Try to supply less value when requesting
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x")
            ).to.be.revertedWithCustomError(balanceTrackerFixedPriceNative, "InsufficientBalance");

            // Create a request
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x", {value: maxDeliveryRate});

            // Try to initialize the mech again
            await expect(
                priorityMech.setUp(data)
            ).to.be.revertedWithCustomError(priorityMech, "AlreadyInitialized");

            // Get the requests count
            let requestsCount = await mechMarketplace.mapRequestCounts(deployer.address);
            expect(requestsCount).to.equal(1);
            requestsCount = await priorityMech.mapUndeliveredRequestsCounts(deployer.address);
            expect(requestsCount).to.equal(1);
            requestsCount = await mechMarketplace.numTotalRequests();
            expect(requestsCount).to.equal(1);

            // Get mech token value
            const registry = await priorityMech.token();
            expect(registry).to.equal(serviceRegistry.address);
        });
    });

    context("Deliver", async function () {
        it("Delivering a request by a priority mech", async function () {
            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Get the non-existent request status
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(0);

            // Try to deliver a non existent request
            await expect(
                priorityMech.deliverToMarketplace(requestId, data)
            ).to.be.revertedWithCustomError(priorityMech, "RequestIdNotFound");

            // Create a request
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x", {value: maxDeliveryRate});

            // Try to deliver not by the service multisig (agent owner)
            await expect(
                priorityMech.connect(signers[1]).deliverToMarketplace(requestId, data)
            ).to.be.reverted;

            // Get the request status (requested priority)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            // Try to deliver request not by the mech
            await expect(
                mechMarketplace.deliverMarketplace(requestId, data)
            ).to.be.reverted;

            // Deliver a request
            await priorityMech.deliverToMarketplace(requestId, data);

            // Get the request status (delivered)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(3);

            // Try to deliver the same request again
            await priorityMech.deliverToMarketplace(requestId, data);

            // Check mech karma
            let mechKarma = await karma.mapMechKarma(priorityMech.address);
            expect(mechKarma).to.equal(1);
            // Check requester mech karma
            mechKarma = await karma.mapRequesterMechKarma(deployer.address, priorityMech.address);
            expect(mechKarma).to.equal(1);
        });

        it("Delivering a request by a priority mech with pre-paid logic", async function () {
            // Get request Id
            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Pre-pay the contract insufficient amount for posting a request
            await deployer.sendTransaction({to: balanceTrackerFixedPriceNative.address, value: maxDeliveryRate - 1});

            // Try to create request with insufficient pre-paid amount
            await expect(
                mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x")
            ).to.be.revertedWithCustomError(balanceTrackerFixedPriceNative, "InsufficientBalance");

            // Pre-pay the contract more for posting a request
            await deployer.sendTransaction({to: balanceTrackerFixedPriceNative.address, value: maxDeliveryRate});

            // Post a request
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x");

            // Get the request status (requested priority)
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            // Deliver a request
            await priorityMech.deliverToMarketplace(requestId, data);

            // Get the request status (delivered)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(3);

            // Try to deliver the same request again
            await priorityMech.deliverToMarketplace(requestId, data);

            // Check mech karma
            let mechKarma = await karma.mapMechKarma(priorityMech.address);
            expect(mechKarma).to.equal(1);
            // Check requester mech karma
            mechKarma = await karma.mapRequesterMechKarma(deployer.address, priorityMech.address);
            expect(mechKarma).to.equal(1);

            // Check priority mech balance now
            let mechBalance = await balanceTrackerFixedPriceNative.mapMechBalances(priorityMech.address);
            expect(mechBalance).to.equal(maxDeliveryRate);

            const balanceBefore = await ethers.provider.getBalance(priorityMech.address);
            // Process payment for mech
            await balanceTrackerFixedPriceNative.processPaymentByMultisig(priorityMech.address);
            const balanceAfter = await ethers.provider.getBalance(priorityMech.address);

            // Check charged fee
            const collectedFees = await balanceTrackerFixedPriceNative.collectedFees();
            // Since the delivery rate is smaller than MAX_FEE_FACTOR, the minimal fee was charged
            expect(collectedFees).to.equal(1);

            // Check mech payout: payment - fee
            const balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(maxDeliveryRate - 1);

            // Check requester leftover balance
            let requesterBalance = await balanceTrackerFixedPriceNative.mapRequesterBalances(deployer.address);
            expect(requesterBalance).to.equal(maxDeliveryRate - 1);

            // Withdraw requester balances
            await balanceTrackerFixedPriceNative.withdraw();
            requesterBalance = await balanceTrackerFixedPriceNative.mapRequesterBalances(deployer.address);
            expect(requesterBalance).to.equal(0);
        });

        it("Delivering a request by a priority mech with pre-paid logic with sufficient balance", async function () {
            // Get request Id
            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Pre-pay the contract insufficient amount for posting a request
            await deployer.sendTransaction({to: balanceTrackerFixedPriceNative.address, value: maxDeliveryRate});

            // Post a request
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x");

            // Try to withdraw mech zero balances
            await expect(
                balanceTrackerFixedPriceNative.withdraw()
            ).to.be.revertedWithCustomError(balanceTrackerFixedPriceNative, "ZeroValue");

            // Try to withdraw zero balances
            await expect(
                balanceTrackerFixedPriceNative.processPaymentByMultisig(priorityMech.address)
            ).to.be.revertedWithCustomError(balanceTrackerFixedPriceNative, "ZeroValue");

            // Deliver a request
            await priorityMech.deliverToMarketplace(requestId, data);

            // Check priority mech balance now
            let mechBalance = await balanceTrackerFixedPriceNative.mapMechBalances(priorityMech.address);
            expect(mechBalance).to.equal(maxDeliveryRate);

            const balanceBefore = await ethers.provider.getBalance(priorityMech.address);
            // Process payment for mech
            await balanceTrackerFixedPriceNative.processPaymentByMultisig(priorityMech.address);
            const balanceAfter = await ethers.provider.getBalance(priorityMech.address);

            // Check charged fee
            const collectedFees = await balanceTrackerFixedPriceNative.collectedFees();
            // Since the delivery rate is smaller than MAX_FEE_FACTOR, the minimal fee was charged
            expect(collectedFees).to.equal(1);

            // Check mech payout: payment - fee
            const balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(maxDeliveryRate - 1);

            // Check requester leftover balance
            let requesterBalance = await balanceTrackerFixedPriceNative.mapRequesterBalances(deployer.address);
            expect(requesterBalance).to.equal(0);

            // Try to withdraw zero balances
            await expect(
                balanceTrackerFixedPriceNative.withdraw()
            ).to.be.revertedWithCustomError(balanceTrackerFixedPriceNative, "ZeroValue");
        });

        it("Delivering a request by a different mech", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Try to deliver a non-existent request
            await expect(
                deliveryMech.deliverToMarketplace(requestId, data)
            ).to.be.revertedWithCustomError(mechMarketplace, "RequestIdNotFound");
            await expect(
                mechMarketplace.deliverMarketplace(requestId, data)
            ).to.be.reverted;

            // Get the non-existent request status
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(0);

            // Create a request
            await mechMarketplace.request(data, mechServiceId, requesterServiceId, minResponseTimeout, "0x", {value: maxDeliveryRate});

            // Try to deliver by a delivery mech right away
            await expect(
                deliveryMech.deliverToMarketplace(requestId, data)
            ).to.be.revertedWithCustomError(mechMarketplace, "PriorityMechResponseTimeout");

            // Get the request status (requested priority)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            // Increase the time such that the request expires for a priority mech
            await helpers.time.increase(maxResponseTimeout);

            // Get the request status (requested expired)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(2);

            // Try to deliver by a mech with bigger max Delivery rate
            await deliveryMech.changeMaxDeliveryRate(maxDeliveryRate + 1);
            await expect(
                deliveryMech.deliverToMarketplace(requestId, data)
            ).to.be.revertedWithCustomError(mechMarketplace, "Overflow");

            // Change max delivery rate back
            await deliveryMech.changeMaxDeliveryRate(maxDeliveryRate);

            // Deliver a request by the delivery mech
            await deliveryMech.deliverToMarketplace(requestId, data);

            // Try to deliver the same request again (gets empty data)
            await deliveryMech.deliverToMarketplace(requestId, data);

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

        it("Getting undelivered requests info", async function () {
            const numRequests = 5;
            const datas = new Array();
            const requestIds = new Array();
            let requestCount = 0;
            for (let i = 0; i < numRequests; i++) {
                datas[i] = data + "00".repeat(i);
            }

            // Get first request Id
            requestIds[0] = await mechMarketplace.getRequestId(deployer.address, datas[0], 0);
            requestCount++;

            // Check request Ids
            let uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);

            // Create a first request
            await mechMarketplace.request(datas[0], mechServiceId, 0, minResponseTimeout, "0x", {value: maxDeliveryRate});

            // Check request Ids
            uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(1);
            expect(uRequestIds[0]).to.equal(requestIds[0]);

            // Deliver a request
            await priorityMech.deliverToMarketplace(requestIds[0], data);

            // Check request Ids
            uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);

            // Update the delivered request in array as one of them was already delivered
            for (let i = 0; i < numRequests; i++) {
                requestIds[i] = await mechMarketplace.getRequestId(deployer.address, datas[i], requestCount);
                requestCount++;
            }

            // Stack all requests
            for (let i = 0; i < numRequests; i++) {
                await mechMarketplace.request(datas[i], mechServiceId, requesterServiceId, minResponseTimeout, "0x", {value: maxDeliveryRate});
            }

            // Check request Ids
            uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests);
            // Requests are added in the reverse order
            for (let i = 0; i < numRequests; i++) {
                expect(uRequestIds[numRequests - i - 1]).to.eq(requestIds[i]);
            }

            // Deliver all requests
            for (let i = 0; i < numRequests; i++) {
                await priorityMech.deliverToMarketplace(requestIds[i], datas[i]);
            }

            // Check request Ids
            uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);

            // Update all requests again and post them
            for (let i = 0; i < numRequests; i++) {
                requestIds[i] = await mechMarketplace.getRequestId(deployer.address, datas[i], requestCount);
                requestCount++;
                await mechMarketplace.request(datas[i], mechServiceId, requesterServiceId, minResponseTimeout, "0x", {value: maxDeliveryRate});
            }

            // Deliver the first request
            await priorityMech.deliverToMarketplace(requestIds[0], datas[0]);

            // Check request Ids
            uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests - 1);
            // Requests are added in the reverse order
            for (let i = 1; i < numRequests; i++) {
                expect(uRequestIds[numRequests - i - 1]).to.eq(requestIds[i]);
            }

            // Deliver the last request
            await priorityMech.deliverToMarketplace(requestIds[numRequests - 1], datas[numRequests - 1]);

            // Check request Ids
            uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests - 2);
            for (let i = 1; i < numRequests - 1; i++) {
                expect(uRequestIds[numRequests - i - 2]).to.eq(requestIds[i]);
            }

            // Deliver the middle request
            const middle = Math.floor(numRequests / 2);
            await priorityMech.deliverToMarketplace(requestIds[middle], datas[middle]);

            // Check request Ids
            uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests - 3);
            for (let i = 1; i < middle; i++) {
                expect(uRequestIds[middle - i]).to.eq(requestIds[i]);
            }
            for (let i = middle + 1; i < numRequests - 1; i++) {
                expect(uRequestIds[numRequests - i - 2]).to.eq(requestIds[i]);
            }
        });

        it("Getting undelivered requests info for even and odd requests", async function () {
            const numRequests = 9;
            const datas = new Array();
            const requestIds = new Array();
            let requestCount = 0;
            // Compute and stack all the requests
            for (let i = 0; i < numRequests; i++) {
                datas[i] = data + "00".repeat(i);
                requestIds[i] = await mechMarketplace.getRequestId(deployer.address, datas[i], requestCount);
                requestCount++;
                await mechMarketplace.request(datas[i], mechServiceId, requesterServiceId, minResponseTimeout, "0x", {value: maxDeliveryRate});
            }

            // Deliver even requests
            for (let i = 0; i < numRequests; i++) {
                if (i % 2 != 0) {
                    await priorityMech.deliverToMarketplace(requestIds[i], datas[i]);
                }
            }

            // Check request Ids
            let uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            const half = Math.floor(numRequests / 2) + 1;
            expect(uRequestIds.length).to.equal(half);
            for (let i = 0; i < half; i++) {
                expect(uRequestIds[half - i - 1]).to.eq(requestIds[i * 2]);
            }

            // Deliver the rest of requests
            for (let i = 0; i < numRequests; i++) {
                if (i % 2 == 0) {
                    await priorityMech.deliverToMarketplace(requestIds[i], datas[i]);
                }
            }

            // Check request Ids
            uRequestIds = await priorityMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);
        });

        it("Getting undelivered requests info for a specified part of a batch", async function () {
            const numRequests = 10;
            const datas = new Array();
            const requestIds = new Array();
            let requestCount = 0;
            // Stack all requests
            for (let i = 0; i < numRequests; i++) {
                datas[i] = data + "00".repeat(i);
                requestIds[i] = await mechMarketplace.getRequestId(deployer.address, datas[i], requestCount);
                requestCount++;
                await mechMarketplace.request(datas[i], mechServiceId, requesterServiceId, minResponseTimeout, "0x", {value: maxDeliveryRate});
            }

            // Check request Ids for just part of the batch
            const half = Math.floor(numRequests / 2);
            // Try to get more elements than there are
            await expect(
                priorityMech.getUndeliveredRequestIds(0, half)
            ).to.be.revertedWithCustomError(priorityMech, "Overflow");

            // Grab the last half of requests
            let uRequestIds = await priorityMech.getUndeliveredRequestIds(half, 0);
            expect(uRequestIds.length).to.equal(half);
            for (let i = 0; i < half; i++) {
                expect(uRequestIds[half - i - 1]).to.eq(requestIds[half + i]);
            }
            // Check for the last element specifically
            expect(uRequestIds[0]).to.eq(requestIds[numRequests - 1]);

            // Grab the last half of requests and a bit more
            uRequestIds = await priorityMech.getUndeliveredRequestIds(half + 2, 0);
            expect(uRequestIds.length).to.equal(half + 2);
            for (let i = 0; i < half + 2; i++) {
                expect(uRequestIds[half + 2 - i - 1]).to.eq(requestIds[half - 2 + i]);
            }

            // Grab the first half of requests
            uRequestIds = await priorityMech.getUndeliveredRequestIds(half, half);
            expect(uRequestIds.length).to.equal(half);
            for (let i = 0; i < half; i++) {
                expect(uRequestIds[numRequests - half - i - 1]).to.eq(requestIds[i]);
            }
            // Check for the first element specifically
            expect(uRequestIds[half - 1]).to.eq(requestIds[0]);

            // Deliver all requests
            for (let i = 0; i < numRequests; i++) {
                await priorityMech.deliverToMarketplace(requestIds[i], datas[i]);
            }
        });
    });

    context("Changing parameters", async function () {
        it("Set another minimum maxDeliveryRate", async function () {
            // Try to change zero delivery rate
            await expect(
                priorityMech.changeMaxDeliveryRate(0)
            ).to.be.reverted;

            await priorityMech.changeMaxDeliveryRate(maxDeliveryRate + 1);

            // Try to change delivery not by the service multisig (agent owner)
            await expect(
                priorityMech.connect(signers[1]).changeMaxDeliveryRate(maxDeliveryRate + 2)
            ).to.be.reverted;
        });
    });
});