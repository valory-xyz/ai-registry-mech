/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe.skip("AgentFactory", function () {
    let serviceRegistry;
    let agentFactory;
    let mechMarketplace;
    let signers;
    const agentHash = "0x" + "5".repeat(64);
    const price = 1;
    beforeEach(async function () {
        signers = await ethers.getSigners();

        const AgentFactory = await ethers.getContractFactory("AgentFactory");
        agentFactory = await AgentFactory.deploy(serviceRegistry.address);
        await agentFactory.deployed();

        const MechMarketplace = await ethers.getContractFactory("MechMarketplace");
        // Note, service registry and karma contract address is irrelevant for this test suite
        mechMarketplace = await MechMarketplace.deploy(agentFactory.address, agentFactory.address,
            agentFactory.address, 10, 10);
        await mechMarketplace.deployed();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await agentFactory.serviceRegistry()).to.equal(serviceRegistry.address);
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
                agentFactory.create(user.address, agentHash, price, mechMarketplace.address)
            ).to.be.revertedWithCustomError(agentFactory, "Paused");

            // Try to unpause not from the owner of the service manager
            await expect(
                agentFactory.connect(user).unpause()
            ).to.be.revertedWithCustomError(agentFactory, "OwnerOnly");

            // Unpause the contract
            await agentFactory.unpause();

            // Mint an agent
            await serviceRegistry.changeManager(agentFactory.address);
            await agentFactory.create(user.address, agentHash, price, mechMarketplace.address);
        });
    });
});
