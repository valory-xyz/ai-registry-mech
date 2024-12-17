/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("MechFixedPrice", function () {
    let MechFixedPrice;
    let serviceRegistry;
    let mechMarketplace;
    let karma;
    let serviceStakingMech;
    let serviceStakingRequester;
    let mechFactoryFixedPrice;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const agentHash = "0x" + "5".repeat(64);
    const price = 1000;
    const data = "0x00";
    const fee = 10;
    const minResponseTimeout = 10;
    const maxResponceTimeout = 20;
    const serviceId = 1;
    const priceData = ethers.utils.defaultAbiCoder.encode(["uint256"], [price]);

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        MechFixedPrice = await ethers.getContractFactory("MechFixedPrice");

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

        // Get two mock staking
        const ServiceStakingMech = await ethers.getContractFactory("MockServiceStaking");
        serviceStakingMech = await ServiceStakingMech.deploy();
        await serviceStakingMech.deployed();

        serviceStakingRequester = await ServiceStakingMech.deploy();
        await serviceStakingMech.deployed();

        // Deploy mech factory
        const MechFactoryFixedPrice = await ethers.getContractFactory("MechFactoryFixedPrice");
        mechFactoryFixedPrice = await MechFactoryFixedPrice.deploy();
        await mechFactoryFixedPrice.deployed();

        // Wrapped native token and buy back burner are not relevant for now
        const MechMarketplace = await ethers.getContractFactory("MechMarketplace");
        mechMarketplace = await MechMarketplace.deploy(serviceRegistry.address, serviceStakingMech.address,
            karma.address, deployer.address, deployer.address);
        await mechMarketplace.deployed();

        // Deploy and initialize marketplace proxy
        proxyData = MechMarketplace.interface.encodeFunctionData("initialize",
            [fee, minResponseTimeout, maxResponceTimeout]);
        const MechMarketplaceProxy = await ethers.getContractFactory("MechMarketplaceProxy");
        const mechMarketplaceProxy = await MechMarketplaceProxy.deploy(mechMarketplace.address, proxyData);
        await mechMarketplaceProxy.deployed();

        mechMarketplace = await ethers.getContractAt("MechMarketplace", mechMarketplaceProxy.address);

        // Whitelist mech factory
        await mechMarketplace.setMechFactoryStatuses([mechFactoryFixedPrice.address], [true]);

        // Whitelist marketplace in the karma proxy
        await karma.setMechMarketplaceStatuses([mechMarketplace.address], [true]);

        // Pseudo-create two services
        await serviceRegistry.setServiceOwner(serviceId, deployer.address);
        await serviceRegistry.setServiceOwner(serviceId + 1, deployer.address);

        // Pseudo-stake mech and requester services
        await serviceStakingMech.setServiceInfo(serviceId, deployer.address);
        await serviceStakingRequester.setServiceInfo(serviceId, deployer.address);
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            // Zero mech marketplace
            await expect(
                MechFixedPrice.deploy(AddressZero, AddressZero, 0, 0)
            ).to.be.revertedWithCustomError(MechFixedPrice, "ZeroAddress");

            // Zero service registry
            await expect(
                MechFixedPrice.deploy(mechMarketplace.address, AddressZero, 0, 0)
            ).to.be.revertedWithCustomError(MechFixedPrice, "ZeroAddress");

            // Zero service Id
            await expect(
                MechFixedPrice.deploy(mechMarketplace.address, serviceRegistry.address, 0, 0)
            ).to.be.revertedWithCustomError(MechFixedPrice, "ZeroValue");

            // Zero price
            await expect(
                MechFixedPrice.deploy(mechMarketplace.address, serviceRegistry.address, serviceId, 0)
            ).to.be.revertedWithCustomError(MechFixedPrice, "ZeroValue");

            // Agent Id does not exist
            await expect(
                MechFixedPrice.deploy(mechMarketplace.address, serviceRegistry.address, serviceId + 2, price)
            ).to.be.reverted;
        });
    });

    context("Request", async function () {
        it.only("Creating an agent mech and doing a request", async function () {
            let tx = await mechMarketplace.create(serviceId, mechFactoryFixedPrice.address, priceData);
            res = await tx.wait();

            // Get mech contract address from the event
            const agentMechAddress = "0x" + res.logs[0].topics[1].slice(26);

            // Get mech contract instance
            const agentMech = await ethers.getContractAt("MechFixedPrice", agentMechAddress);

            // Try to post a request directly to the mech
            await expect(
                agentMech.requestFromMarketplace(deployer.address, price, data, 0)
            ).to.be.revertedWithCustomError(agentMech, "MarketplaceNotAuthorized");

            // Try to request to a zero priority mech
            await expect(
                mechMarketplace.request("0x", AddressZero, AddressZero, 0, AddressZero, 0, 0)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroAddress");

            // Response time is out of bounds
            await expect(
                mechMarketplace.request("0x", serviceRegistry.address, serviceStakingMech.address, 0,
                    serviceStakingRequester.address, 0, 0)
            ).to.be.revertedWithCustomError(mechMarketplace, "OutOfBounds");

            // Response time is out of bounds
            await expect(
                mechMarketplace.request("0x", serviceRegistry.address, serviceStakingMech.address, 0,
                    serviceStakingRequester.address, 0, minResponseTimeout - 1)
            ).to.be.revertedWithCustomError(mechMarketplace, "OutOfBounds");
            await expect(
                mechMarketplace.request("0x", serviceRegistry.address, serviceStakingMech.address, 0,
                    serviceStakingRequester.address, 0, maxResponceTimeout + 1)
            ).to.be.revertedWithCustomError(mechMarketplace, "OutOfBounds");
            // Change max response timeout close to type(uint32).max
            //const closeToMaxUint96 = "4294967295";
            //await mechMarketplace.deploy(minResponseTimeout, closeToMaxUint96);
            //await expect(
            //    mechMarketplace.request("0x", agentMech.address, closeToMaxUint96)
            //).to.be.revertedWithCustomError(mechMarketplace, "Overflow");

            // Try to request to a mech with an empty data
            await expect(
                mechMarketplace.request("0x", serviceRegistry.address, serviceStakingMech.address, 0,
                    serviceStakingRequester.address, 0, minResponseTimeout)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroValue");

            // Try to request to a mech with a zero service Id
            await expect(
                mechMarketplace.request(data, serviceRegistry.address, serviceStakingMech.address, 0,
                    serviceStakingRequester.address, 0, minResponseTimeout)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroValue");

            // Try to request to a mech with an incorrect mech and staking instance address
            await expect(
                mechMarketplace.request(data, serviceRegistry.address, serviceStakingMech.address, serviceId,
                    serviceStakingRequester.address, 0, minResponseTimeout)
            ).to.be.reverted;

            // Try to request to a mech with an incorrect mech service Id
            await expect(
                mechMarketplace.request(data, agentMech.address, serviceStakingMech.address, serviceId + 1,
                    serviceStakingRequester.address, 0, minResponseTimeout)
            ).to.be.revertedWithCustomError(mechMarketplace, "UnauthorizedAccount");

            // Try to request to a mech with an incorrect requester service Id
            await expect(
                mechMarketplace.request(data, agentMech.address, serviceStakingMech.address, serviceId,
                    serviceStakingRequester.address, 0, minResponseTimeout)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroValue");

            // Try to request to a mech with an incorrect requester service Id
            await expect(
                mechMarketplace.request(data, agentMech.address, serviceStakingMech.address, serviceId,
                    serviceStakingRequester.address, 0, minResponseTimeout)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroValue");

            // Try to supply less value when requesting
            await expect(
                mechMarketplace.request(data, agentMech.address, serviceStakingMech.address, serviceId,
                    serviceStakingRequester.address, serviceId, minResponseTimeout)
            ).to.be.revertedWithCustomError(agentMech, "NotEnoughPaid");

            // Create a request
            await mechMarketplace.request(data, agentMech.address, serviceStakingMech.address, serviceId,
                serviceStakingRequester.address, serviceId, minResponseTimeout, {value: price});

            // Get the requests count
            let requestsCount = await agentMech.getRequestsCount(deployer.address);
            expect(requestsCount).to.equal(1);
            requestsCount = await mechMarketplace.numTotalRequests();
            expect(requestsCount).to.equal(1);
        });
    });

    context("Deliver", async function () {
        it("Delivering a request by a priority mech", async function () {
            const agentMech = await MechFixedPrice.deploy(serviceRegistry.address, serviceId, price, mechMarketplace.address);
            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Get the non-existent request status
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(0);

            // Try to deliver not via a Marketplace when the Marketplace exists
            await expect(
                agentMech.deliver(requestId, data)
            ).to.be.revertedWithCustomError(agentMech, "MarketplaceExists");

            // Try to deliver a non existent request
            await expect(
                agentMech.deliverToMarketplace(requestId, data, serviceStakingMech.address, serviceId)
            ).to.be.revertedWithCustomError(agentMech, "RequestIdNotFound");

            // Create a request
            await mechMarketplace.request(data, agentMech.address, serviceStakingMech.address, serviceId,
                serviceStakingRequester.address, serviceId, minResponseTimeout, {value: price});

            // Try to deliver not by the operator (agent owner)
            await expect(
                agentMech.connect(signers[1]).deliverToMarketplace(requestId, data, serviceStakingMech.address, serviceId)
            ).to.be.reverted;

            // Get the request status (requested priority)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            // Try to deliver request not by the mech
            await expect(
                mechMarketplace.deliverMarketplace(requestId, data, serviceStakingMech.address, serviceId)
            ).to.be.reverted;

            // Deliver a request
            await agentMech.deliverToMarketplace(requestId, data, serviceStakingMech.address, serviceId);

            // Get the request status (delivered)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(3);

            // Try to deliver the same request again
            await agentMech.deliverToMarketplace(requestId, data, serviceStakingMech.address, serviceId);

            // Check mech karma
            let mechKarma = await karma.mapMechKarma(agentMech.address);
            expect(mechKarma).to.equal(1);
            // Check requester mech karma
            mechKarma = await karma.mapRequesterMechKarma(deployer.address, agentMech.address);
            expect(mechKarma).to.equal(1);
        });

        it("Delivering a request by a different mech", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const priorityMech = await MechFixedPrice.deploy(serviceRegistry.address, serviceId, price, mechMarketplace.address);
            const deliveryMech = await MechFixedPrice.deploy(serviceRegistry.address, serviceId + 1, price, mechMarketplace.address);
            // Register the info for the delivery service mech
            await serviceStakingMech.setServiceInfo(serviceId + 1, deployer.address);

            const requestId = await mechMarketplace.getRequestId(deployer.address, data, 0);

            // Get the non-existent request status
            let status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(0);

            // Create a request
            await mechMarketplace.request(data, priorityMech.address, serviceStakingMech.address, serviceId,
                serviceStakingRequester.address, serviceId, minResponseTimeout, {value: price});

            // Try to deliver by a delivery mech right away
            await expect(
                deliveryMech.deliverToMarketplace(requestId, data, serviceStakingMech.address, serviceId + 1)
            ).to.be.revertedWithCustomError(mechMarketplace, "PriorityMechResponseTimeout");

            // Get the request status (requested priority)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(1);

            // Increase the time such that the request expires for a priority mech
            await helpers.time.increase(maxResponceTimeout);

            // Get the request status (requested expired)
            status = await mechMarketplace.getRequestStatus(requestId);
            expect(status).to.equal(2);

            // Deliver a request by the delivery mech
            await deliveryMech.deliverToMarketplace(requestId, data, serviceStakingMech.address, serviceId + 1);

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
            const agentMech = await MechFixedPrice.deploy(serviceRegistry.address, serviceId, price, mechMarketplace.address);

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
            let uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);

            // Create a first request
            await mechMarketplace.request(datas[0], agentMech.address, serviceStakingMech.address, serviceId,
                serviceStakingRequester.address, serviceId, minResponseTimeout, {value: price});

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(1);
            expect(uRequestIds[0]).to.equal(requestIds[0]);

            // Deliver a request
            await agentMech.deliverToMarketplace(requestIds[0], data, serviceStakingMech.address, serviceId);

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);

            // Update the delivered request in array as one of them was already delivered
            for (let i = 0; i < numRequests; i++) {
                requestIds[i] = await mechMarketplace.getRequestId(deployer.address, datas[i], requestCount);
                requestCount++;
            }

            // Stack all requests
            for (let i = 0; i < numRequests; i++) {
                await mechMarketplace.request(datas[i], agentMech.address, serviceStakingMech.address, serviceId,
                    serviceStakingRequester.address, serviceId, minResponseTimeout, {value: price});
            }

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests);
            // Requests are added in the reverse order
            for (let i = 0; i < numRequests; i++) {
                expect(uRequestIds[numRequests - i - 1]).to.eq(requestIds[i]);
            }

            // Deliver all requests
            for (let i = 0; i < numRequests; i++) {
                await agentMech.deliverToMarketplace(requestIds[i], datas[i], serviceStakingMech.address, serviceId);
            }

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);

            // Update all requests again and post them
            for (let i = 0; i < numRequests; i++) {
                requestIds[i] = await mechMarketplace.getRequestId(deployer.address, datas[i], requestCount);
                requestCount++;
                await mechMarketplace.request(datas[i], agentMech.address, serviceStakingMech.address, serviceId,
                    serviceStakingRequester.address, serviceId, minResponseTimeout, {value: price});
            }

            // Deliver the first request
            await agentMech.deliverToMarketplace(requestIds[0], datas[0], serviceStakingMech.address, serviceId);

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests - 1);
            // Requests are added in the reverse order
            for (let i = 1; i < numRequests; i++) {
                expect(uRequestIds[numRequests - i - 1]).to.eq(requestIds[i]);
            }

            // Deliver the last request
            await agentMech.deliverToMarketplace(requestIds[numRequests - 1], datas[numRequests - 1],
                serviceStakingMech.address, serviceId);

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests - 2);
            for (let i = 1; i < numRequests - 1; i++) {
                expect(uRequestIds[numRequests - i - 2]).to.eq(requestIds[i]);
            }

            // Deliver the middle request
            const middle = Math.floor(numRequests / 2);
            await agentMech.deliverToMarketplace(requestIds[middle], datas[middle], serviceStakingMech.address, serviceId);

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests - 3);
            for (let i = 1; i < middle; i++) {
                expect(uRequestIds[middle - i]).to.eq(requestIds[i]);
            }
            for (let i = middle + 1; i < numRequests - 1; i++) {
                expect(uRequestIds[numRequests - i - 2]).to.eq(requestIds[i]);
            }
        });

        it("Getting undelivered requests info for even and odd requests", async function () {
            const agentMech = await MechFixedPrice.deploy(serviceRegistry.address, serviceId, price, mechMarketplace.address);

            const numRequests = 9;
            const datas = new Array();
            const requestIds = new Array();
            let requestCount = 0;
            // Compute and stack all the requests
            for (let i = 0; i < numRequests; i++) {
                datas[i] = data + "00".repeat(i);
                requestIds[i] = await mechMarketplace.getRequestId(deployer.address, datas[i], requestCount);
                requestCount++;
                await mechMarketplace.request(datas[i], agentMech.address, serviceStakingMech.address, serviceId,
                    serviceStakingRequester.address, serviceId, minResponseTimeout, {value: price});
            }

            // Deliver even requests
            for (let i = 0; i < numRequests; i++) {
                if (i % 2 != 0) {
                    await agentMech.deliverToMarketplace(requestIds[i], datas[i], serviceStakingMech.address, serviceId);
                }
            }

            // Check request Ids
            let uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            const half = Math.floor(numRequests / 2) + 1;
            expect(uRequestIds.length).to.equal(half);
            for (let i = 0; i < half; i++) {
                expect(uRequestIds[half - i - 1]).to.eq(requestIds[i * 2]);
            }

            // Deliver the rest of requests
            for (let i = 0; i < numRequests; i++) {
                if (i % 2 == 0) {
                    await agentMech.deliverToMarketplace(requestIds[i], datas[i], serviceStakingMech.address, serviceId);
                }
            }

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);
        });

        it("Getting undelivered requests info for a specified part of a batch", async function () {
            const agentMech = await MechFixedPrice.deploy(serviceRegistry.address, serviceId, price, mechMarketplace.address);

            const numRequests = 10;
            const datas = new Array();
            const requestIds = new Array();
            let requestCount = 0;
            // Stack all requests
            for (let i = 0; i < numRequests; i++) {
                datas[i] = data + "00".repeat(i);
                requestIds[i] = await mechMarketplace.getRequestId(deployer.address, datas[i], requestCount);
                requestCount++;
                await mechMarketplace.request(datas[i], agentMech.address, serviceStakingMech.address, serviceId,
                    serviceStakingRequester.address, serviceId, minResponseTimeout, {value: price});
            }

            // Check request Ids for just part of the batch
            const half = Math.floor(numRequests / 2);
            // Try to get more elements than there are
            await expect(
                agentMech.getUndeliveredRequestIds(0, half)
            ).to.be.revertedWithCustomError(agentMech, "Overflow");

            // Grab the last half of requests
            let uRequestIds = await agentMech.getUndeliveredRequestIds(half, 0);
            expect(uRequestIds.length).to.equal(half);
            for (let i = 0; i < half; i++) {
                expect(uRequestIds[half - i - 1]).to.eq(requestIds[half + i]);
            }
            // Check for the last element specifically
            expect(uRequestIds[0]).to.eq(requestIds[numRequests - 1]);

            // Grab the last half of requests and a bit more
            uRequestIds = await agentMech.getUndeliveredRequestIds(half + 2, 0);
            expect(uRequestIds.length).to.equal(half + 2);
            for (let i = 0; i < half + 2; i++) {
                expect(uRequestIds[half + 2 - i - 1]).to.eq(requestIds[half - 2 + i]);
            }

            // Grab the first half of requests
            uRequestIds = await agentMech.getUndeliveredRequestIds(half, half);
            expect(uRequestIds.length).to.equal(half);
            for (let i = 0; i < half; i++) {
                expect(uRequestIds[numRequests - half - i - 1]).to.eq(requestIds[i]);
            }
            // Check for the first element specifically
            expect(uRequestIds[half - 1]).to.eq(requestIds[0]);

            // Deliver all requests
            for (let i = 0; i < numRequests; i++) {
                await agentMech.deliverToMarketplace(requestIds[i], datas[i], serviceStakingMech.address, serviceId);
            }
        });
    });

    context("Changing parameters", async function () {
        it("Set another minimum price", async function () {
            const agentMech = await MechFixedPrice.deploy(serviceRegistry.address, serviceId, price, mechMarketplace.address);
            await agentMech.setPrice(price + 1);

            // Try to set price not by the operator (agent owner)
            await expect(
                agentMech.connect(signers[1]).setPrice(price + 2)
            ).to.be.reverted;
        });
    });
});
