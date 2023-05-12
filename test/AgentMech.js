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

            await agentMech.request(data, {value: price});
        });
    });

    context("Deliver", async function () {
        it("Delivering a request", async function () {
            const account = signers[1];
            const agentMech = await AgentMech.deploy(agentRegistry.address, unitId, price);
            const requestId = await agentMech.getRequestId(deployer.address, data);
            await agentMech.deliver(requestId, data);

            // Try to deliver not by the operator (agent owner)
            await expect(
                agentMech.connect(account).request(data)
            ).to.be.reverted;
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
