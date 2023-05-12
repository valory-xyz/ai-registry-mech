/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AgentFactory", function () {
    let agentRegistry;
    let agentFactory;
    let signers;
    const agentHash = "0x" + "5".repeat(64);
    const price = 1;
    beforeEach(async function () {
        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/");
        await agentRegistry.deployed();

        const AgentFactory = await ethers.getContractFactory("AgentFactory");
        agentFactory = await AgentFactory.deploy(agentRegistry.address);
        await agentFactory.deployed();

        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await agentFactory.agentRegistry()).to.equal(agentRegistry.address);
        });

        it("Pausing and unpausing", async function () {
            const user = signers[3];

            // Try to pause not from the owner of the service manager
            await expect(
                agentFactory.connect(user).pause()
            ).to.be.revertedWithCustomError(agentFactory, "OwnerOnly");

            // Pause the contract
            await agentFactory.pause();

            // Try minting when paused
            await expect(
                agentFactory.create(user.address, agentHash, price)
            ).to.be.revertedWithCustomError(agentFactory, "Paused");

            // Try to unpause not from the owner of the service manager
            await expect(
                agentFactory.connect(user).unpause()
            ).to.be.revertedWithCustomError(agentFactory, "OwnerOnly");

            // Unpause the contract
            await agentFactory.unpause();

            // Mint an agent
            await agentRegistry.changeManager(agentFactory.address);
            await agentFactory.create(user.address, agentHash, price);
        });
    });
});
