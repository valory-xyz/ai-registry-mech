/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AgentRegistry", function () {
    let agentRegistry;
    let reentrancyAttacker;
    let signers;
    const agentHash = "0x" + "9".repeat(64);
    const agentHash1 = "0x" + "1".repeat(64);
    const agentHash2 = "0x" + "2".repeat(64);
    const AddressZero = "0x" + "0".repeat(40);
    const ZeroBytes32 = "0x" + "0".repeat(64);
    beforeEach(async function () {
        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/");
        await agentRegistry.deployed();

        const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyAttacker");
        reentrancyAttacker = await ReentrancyAttacker.deploy(agentRegistry.address);
        await reentrancyAttacker.deployed();

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

        it("Should fail when creating an agent with a zero owner address", async function () {
            const agentFactory = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(agentFactory.address);
            await expect(
                agentRegistry.connect(agentFactory).create(user.address, ZeroBytes32)
            ).to.be.revertedWithCustomError(agentRegistry, "ZeroValue");
        });

        it("Token Id=1 after first successful agent creation must exist ", async function () {
            const agentFactory = signers[1];
            const user = signers[2];
            const tokenId = 1;
            await agentRegistry.changeManager(agentFactory.address);
            await agentRegistry.connect(agentFactory).create(user.address, agentHash);
            expect(await agentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await agentRegistry.exists(tokenId)).to.equal(true);

            // Check the token URI
            const baseURI = "https://localhost/agent/";
            const cidPrefix = "f01701220";
            expect(await agentRegistry.tokenURI(1)).to.equal(baseURI + cidPrefix + "9".repeat(64));

            // Try to return a token URI of a non-existent unit Id
            await expect(
                agentRegistry.tokenURI(2)
            ).to.be.revertedWithCustomError(agentRegistry, "UnitNotFound");
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
                agentRegistry.updateHash(1, agentHash2)
            ).to.be.revertedWithCustomError(agentRegistry, "OperatorOnly");
            await expect(
                agentRegistry.updateHash(2, agentHash2)
            ).to.be.revertedWithCustomError(agentRegistry, "OperatorOnly");
            await agentRegistry.connect(user).updateHash(1, agentHash2);
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

            // Try to update with a zero hash
            await expect(
                agentRegistry.connect(user).updateHash(1, ZeroBytes32)
            ).to.be.revertedWithCustomError(agentRegistry, "ZeroValue");

            // Update hashes
            await agentRegistry.connect(user).updateHash(1, agentHash1);
            await agentRegistry.connect(user).updateHash(1, agentHash2);

            // Get unit hashes and compare
            const hashes = await agentRegistry.getHashes(1);
            expect(hashes.numHashes).to.equal(3);
            expect(hashes.unitHashes[0]).to.equal(agentHash);
            expect(hashes.unitHashes[1]).to.equal(agentHash1);
            expect(hashes.unitHashes[2]).to.equal(agentHash2);
        });
    });

    context("Reentrancy attack", async function () {
        it("Reentrancy attack by the manager during the service creation", async function () {
            // Change the manager to the attacker contract address
            await agentRegistry.changeManager(reentrancyAttacker.address);

            // Simulate the reentrancy attack
            await expect(
                reentrancyAttacker.createBadAgent(reentrancyAttacker.address, agentHash)
            ).to.be.revertedWithCustomError(agentRegistry, "ReentrancyGuard");
        });
    });
});
