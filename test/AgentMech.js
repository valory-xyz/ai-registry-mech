/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AgentMech", function () {
    let AgentMech;
    let agentRegistry;
    let signers;
    let deployer;
    const agentHash = "0x" + "5".repeat(64);
    const AddressZero = "0x" + "0".repeat(40);
    const unitId = 1;
    const price = 1;
    const data = "0x";
    beforeEach(async function () {
        AgentMech = await ethers.getContractFactory("AgentMech");

        // Get the agent registry contract
        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/");
        await agentRegistry.deployed();

        signers = await ethers.getSigners();
        deployer = signers[0];

        // Mint one agent
        await agentRegistry.changeManager(deployer.address);
        await agentRegistry.create(deployer.address, agentHash);
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            await expect(
                AgentMech.deploy(AddressZero, unitId, price)
            ).to.be.reverted;

            await expect(
                AgentMech.deploy(agentRegistry.address, unitId + 1, price)
            ).to.be.reverted;
        });
    });

    context("Request", async function () {
        it("Creating an agent mech and doing a request", async function () {
            const agentMech = await AgentMech.deploy(agentRegistry.address, unitId, price);

            // Try to supply less value when requesting
            await expect(
                agentMech.request(data)
            ).to.be.revertedWithCustomError(agentMech, "NotEnoughPaid");

            // Create a request
            await agentMech.request(data, {value: price});

            // Get the requests count
            const requestsCount = await agentMech.getRequestsCount(deployer.address);
            expect(requestsCount).to.equal(1);
        });
    });

    context("Deliver", async function () {
        it("Delivering a request", async function () {
            const account = signers[1];
            const agentMech = await AgentMech.deploy(agentRegistry.address, unitId, price);

            const requestId = await agentMech.getRequestId(deployer.address, data);
            const requestIdWithNonce = await agentMech.getRequestIdWithNonce(deployer.address, data, 0);

            // Get the non-existent request status
            let status = await agentMech.getRequestStatus(requestIdWithNonce);
            expect(status).to.equal(0);

            // Try to deliver a non existent request
            await expect(
                agentMech.deliver(requestId, requestIdWithNonce, data)
            ).to.be.revertedWithCustomError(agentMech, "RequestIdNotFound");

            // Create a request
            await agentMech.request(data, {value: price});

            // Try to deliver not by the operator (agent owner)
            await expect(
                agentMech.connect(account).deliver(requestId, requestIdWithNonce, data)
            ).to.be.reverted;

            // Get the request status (requested)
            status = await agentMech.getRequestStatus(requestIdWithNonce);
            expect(status).to.equal(1);

            // Deliver a request
            await agentMech.deliver(requestId, requestIdWithNonce, data);

            // Get the request status (delivered)
            status = await agentMech.getRequestStatus(requestIdWithNonce);
            expect(status).to.equal(2);
        });

        it("Getting undelivered requests info", async function () {
            const agentMech = await AgentMech.deploy(agentRegistry.address, unitId, price);

            const numRequests = 5;
            const datas = new Array();
            const requestIdSimple = new Array();
            const requestIds = new Array();
            let requestCount = 0;
            for (let i = 0; i < numRequests; i++) {
                datas[i] = data + "00".repeat(i);
            }

            // Get first request Id
            requestIdSimple[0] = await agentMech.getRequestId(deployer.address, datas[0])
            requestIds[0] = await agentMech.getRequestIdWithNonce(deployer.address, datas[0], 0);
            requestCount++;

            // Check request Ids
            let uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);

            // Create a first request
            await agentMech.request(datas[0], {value: price});

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(1);
            expect(uRequestIds[0]).to.equal(requestIds[0]);

            // Deliver a request
            await agentMech.deliver(requestIdSimple[0], requestIds[0], data);

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);

            // Update the delivered request in array as one of them was already delivered
            for (let i = 0; i < numRequests; i++) {
                requestIds[i] = await agentMech.getRequestIdWithNonce(deployer.address, datas[i], requestCount);
                requestCount++;
            }

            // Stack all requests
            for (let i = 0; i < numRequests; i++) {
                requestIdSimple[i] = await agentMech.getRequestId(deployer.address, datas[i])
                await agentMech.request(datas[i], {value: price});
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
                await agentMech.deliver(requestIdSimple[i], requestIds[i], datas[i]);
            }

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);

            // Update all requests again and post them
            for (let i = 0; i < numRequests; i++) {
                requestIdSimple[i] = await agentMech.getRequestId(deployer.address, datas[i])
                requestIds[i] = await agentMech.getRequestIdWithNonce(deployer.address, datas[i], requestCount);
                requestCount++;
                await agentMech.request(datas[i], {value: price});
            }

            // Deliver the first request
            await agentMech.deliver(requestIdSimple[0], requestIds[0], datas[0]);

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests - 1);
            // Requests are added in the reverse order
            for (let i = 1; i < numRequests; i++) {
                expect(uRequestIds[numRequests - i - 1]).to.eq(requestIds[i]);
            }

            // Deliver the last request
            await agentMech.deliver(requestIdSimple[numRequests - 1], requestIds[numRequests - 1], datas[numRequests - 1]);

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(numRequests - 2);
            for (let i = 1; i < numRequests - 1; i++) {
                expect(uRequestIds[numRequests - i - 2]).to.eq(requestIds[i]);
            }

            // Deliver the middle request
            const middle = Math.floor(numRequests / 2);
            await agentMech.deliver(requestIdSimple[middle], requestIds[middle], datas[middle]);

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
            const agentMech = await AgentMech.deploy(agentRegistry.address, unitId, price);

            const numRequests = 9;
            const datas = new Array();
            const requestIdSimple = new Array();
            const requestIds = new Array();
            let requestCount = 0;
            // Compute and stack all the requests
            for (let i = 0; i < numRequests; i++) {
                datas[i] = data + "00".repeat(i);
                requestIdSimple[i] = await agentMech.getRequestId(deployer.address, datas[i]);
                requestIds[i] = await agentMech.getRequestIdWithNonce(deployer.address, datas[i], requestCount);
                requestCount++;
                await agentMech.request(datas[i], {value: price});
            }

            // Deliver even requests
            for (let i = 0; i < numRequests; i++) {
                if (i % 2 != 0) {
                    await agentMech.deliver(requestIdSimple[i], requestIds[i], datas[i]);
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
                    await agentMech.deliver(requestIdSimple[i], requestIds[i], datas[i]);
                }
            }

            // Check request Ids
            uRequestIds = await agentMech.getUndeliveredRequestIds(0, 0);
            expect(uRequestIds.length).to.equal(0);
        });

        it("Getting undelivered requests info for a specified part of a batch", async function () {
            const agentMech = await AgentMech.deploy(agentRegistry.address, unitId, price);

            const numRequests = 10;
            const datas = new Array();
            const requestIdSimple = new Array();
            const requestIds = new Array();
            let requestCount = 0;
            // Stack all requests
            for (let i = 0; i < numRequests; i++) {
                datas[i] = data + "00".repeat(i);
                requestIdSimple[i] = await agentMech.getRequestId(deployer.address, datas[i]);
                requestIds[i] = await agentMech.getRequestIdWithNonce(deployer.address, datas[i], requestCount);
                requestCount++;
                await agentMech.request(datas[i], {value: price});
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
                await agentMech.deliver(requestIdSimple[i], requestIds[i], datas[i]);
            }
        });
    });

    context("Changing parameters", async function () {
        it("Set another minimum price", async function () {
            const account = signers[1];
            const agentMech = await AgentMech.deploy(agentRegistry.address, unitId, price);
            await agentMech.setPrice(price + 1);

            // Try to set price not by the operator (agent owner)
            await expect(
                agentMech.connect(account).setPrice(price + 2)
            ).to.be.reverted;
        });
    });
});
