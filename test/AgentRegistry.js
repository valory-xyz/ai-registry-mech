/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AgentRegistry", function () {
    let componentRegistry;
    let agentRegistry;
    let signers;
    const agentHash = "0x" + "9".repeat(64);
    const agentHash1 = "0x" + "1".repeat(64);
    const agentHash2 = "0x" + "2".repeat(64);
    const AddressZero = "0x" + "0".repeat(40);
    beforeEach(async function () {
        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/");
        await agentRegistry.deployed();
        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await agentRegistry.name()).to.equal("agent");
            expect(await agentRegistry.symbol()).to.equal("MECH");
            expect(await agentRegistry.baseURI()).to.equal("https://localhost/agent/");
        });

        it("Should fail when checking for the token id existence", async function () {
            const tokenId = 0;
            expect(await agentRegistry.exists(tokenId)).to.equal(false);
        });

        it("Should fail when trying to change the agentFactory from a different address", async function () {
            await expect(
                agentRegistry.connect(signers[1]).changeManager(signers[1].address)
            ).to.be.revertedWithCustomError(agentRegistry, "OwnerOnly");
        });

        it("Setting the base URI", async function () {
            await agentRegistry.setBaseURI("https://localhost2/agent/");
            expect(await agentRegistry.baseURI()).to.equal("https://localhost2/agent/");
        });
    });

    context("Agent creation", async function () {
        it("Should fail when creating an agent without a agentFactory", async function () {
            const user = signers[2];
            await expect(
                agentRegistry.create(user.address, agentHash)
            ).to.be.revertedWithCustomError(agentRegistry, "ManagerOnly");
        });

        it("Should fail when creating an agent with a zero owner address", async function () {
            const agentFactory = signers[1];
            await agentRegistry.changeManager(agentFactory.address);
            await expect(
                agentRegistry.connect(agentFactory).create(AddressZero, agentHash)
            ).to.be.revertedWithCustomError(agentRegistry, "ZeroAddress");
        });

        it("Token Id=1 after first successful agent creation must exist ", async function () {
            const agentFactory = signers[1];
            const user = signers[2];
            const tokenId = 1;
            await agentRegistry.changeManager(agentFactory.address);
            await agentRegistry.connect(agentFactory).create(user.address,
                agentHash);
            expect(await agentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await agentRegistry.exists(tokenId)).to.equal(true);
        });

        it("Catching \"Transfer\" event log after successful creation of an agent", async function () {
            const agentFactory = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(agentFactory.address);
            const agent = await agentRegistry.connect(agentFactory).create(user.address, agentHash);
            const result = await agent.wait();
            expect(result.events[0].event).to.equal("Transfer");
        });
    });

    context("Updating hashes", async function () {
        it("Should fail when the agent does not belong to the owner or IPFS hash is invalid", async function () {
            const agentFactory = signers[1];
            const user = signers[2];
            const user2 = signers[3];
            await agentRegistry.changeManager(agentFactory.address);
            await agentRegistry.connect(agentFactory).create(user.address,
                agentHash);
            await agentRegistry.connect(agentFactory).create(user2.address,
                agentHash1);
            await expect(
                agentRegistry.updateHash(user2.address, 1, agentHash2)
            ).to.be.revertedWithCustomError(agentRegistry, "OperatorOnly");
            await expect(
                agentRegistry.updateHash(user.address, 2, agentHash2)
            ).to.be.revertedWithCustomError(agentRegistry, "OperatorOnly");
            await agentRegistry.connect(agentFactory).updateHash(user.address, 1, agentHash2);
        });

        it("Should return zeros when getting hashes of non-existent agent", async function () {
            const agentFactory = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(agentFactory.address);
            await agentRegistry.connect(agentFactory).create(user.address, agentHash);

            await expect(
                agentRegistry.getHashes(2)
            ).to.be.revertedWithCustomError(agentRegistry, "UnitNotFound");
        });

        it("Update hash, get component hashes", async function () {
            const agentFactory = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(agentFactory.address);
            await agentRegistry.connect(agentFactory).create(user.address,
                agentHash);
            await agentRegistry.connect(agentFactory).updateHash(user.address, 1, agentHash1);
            await agentRegistry.connect(agentFactory).updateHash(user.address, 1, agentHash2);

            const hashes = await agentRegistry.getHashes(1);
            expect(hashes.numHashes).to.equal(3);
            expect(hashes.unitHashes[0]).to.equal(agentHash);
            expect(hashes.unitHashes[1]).to.equal(agentHash1);
            expect(hashes.unitHashes[2]).to.equal(agentHash2);
        });
    });
});
