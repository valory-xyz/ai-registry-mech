/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("MechMarketplace", function () {
    let MechMarketplace;
    let priorityMechAddress;
    let priorityMech;
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
    const requesterServiceId = 2;
    let paymentTypeHash;
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
        MechMarketplace = await ethers.getContractFactory("MechMarketplace");
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

        // Pseudo-create a requester service
        await serviceRegistry.setServiceOwner(requesterServiceId, signers[1].address);

        // Create default priority mech
        let tx = await mechMarketplace.create(mechServiceId, mechFactoryFixedPrice.address, mechCreationData);
        let res = await tx.wait();
        // Get mech contract address from the event
        priorityMechAddress = "0x" + res.logs[0].topics[1].slice(26);
        // Get mech contract instance
        priorityMech = await ethers.getContractAt("MechFixedPriceNative", priorityMechAddress);

        // Deploy
        const BalanceTrackerFixedPriceNative = await ethers.getContractFactory("BalanceTrackerFixedPriceNative");
        balanceTrackerFixedPriceNative = await BalanceTrackerFixedPriceNative.deploy(mechMarketplace.address,
            deployer.address, deployer.address);
        await balanceTrackerFixedPriceNative.deployed();

        // Whitelist balance tracker
        paymentTypeHash = await priorityMech.paymentType();
        await mechMarketplace.setPaymentTypeBalanceTrackers([paymentTypeHash], [balanceTrackerFixedPriceNative.address]);
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            // Zero service registry
            await expect(
                MechMarketplace.deploy(AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroAddress");

            // Zero karma
            await expect(
                MechMarketplace.deploy(serviceRegistry.address, AddressZero)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroAddress");

            // Try to initialize again
            await expect(
                mechMarketplace.initialize(fee, minResponseTimeout, maxResponseTimeout)
            ).to.be.revertedWithCustomError(mechMarketplace, "AlreadyInitialized");
        });

        it("Change owner", async function () {
            // Trying to change owner from a non-owner account address
            await expect(
                mechMarketplace.connect(signers[1]).changeOwner(signers[1].address)
            ).to.be.revertedWithCustomError(mechMarketplace, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                mechMarketplace.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroAddress");

            // Changing the owner
            await mechMarketplace.connect(deployer).changeOwner(signers[1].address);

            // Trying to change owner from the previous owner address
            await expect(
                mechMarketplace.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(mechMarketplace, "OwnerOnly");

            // Change the owner back
            await mechMarketplace.connect(signers[1]).changeOwner(deployer.address);
        });

        it("Change implementation", async function () {
            // Trying to change implementation from a non-owner account address
            await expect(
                mechMarketplace.connect(signers[1]).changeImplementation(mechMarketplace.address)
            ).to.be.revertedWithCustomError(mechMarketplace, "OwnerOnly");

            // Trying to change implementation for the zero address
            await expect(
                mechMarketplace.connect(deployer).changeImplementation(AddressZero)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroAddress");

            // Changing the implementation
            await mechMarketplace.connect(deployer).changeOwner(mechMarketplace.address);
        });

        it("Change marketplace params", async function () {
            // Trying to change params not by the owner
            await expect(
                mechMarketplace.connect(signers[1]).changeMarketplaceParams(0, 0, 0)
            ).to.be.revertedWithCustomError(mechMarketplace, "OwnerOnly");

            // Trying to change params to zeros
            await expect(
                mechMarketplace.changeMarketplaceParams(0, 0, 0)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroValue");
            await expect(
                mechMarketplace.changeMarketplaceParams(10, 0, 0)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroValue");
            await expect(
                mechMarketplace.changeMarketplaceParams(10, 10, 0)
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroValue");

            // Trying to change fee bigger than allowed
            await expect(
                mechMarketplace.changeMarketplaceParams(10001, 1, 2)
            ).to.be.revertedWithCustomError(mechMarketplace, "Overflow");

            // Trying to set the min response bigger than max response timeout
            await expect(
                mechMarketplace.changeMarketplaceParams(10, 10, 1)
            ).to.be.revertedWithCustomError(mechMarketplace, "Overflow");

            // Trying to set max response timeout bigger than the limit
            const maxUint96 = "4294967297";
            await expect(
                mechMarketplace.changeMarketplaceParams(10, 10, maxUint96)
            ).to.be.revertedWithCustomError(mechMarketplace, "Overflow");
        });

        it("Factories and balance trackers", async function () {
            // Trying to call create not by the authorized factory
            await expect(
                mechMarketplace.create(mechServiceId, deployer.address, mechCreationData)
            ).to.be.revertedWithCustomError(mechMarketplace, "UnauthorizedAccount");

            // Trying to set mech factory statuses and balance trackersnot by the owner
            await expect(
                mechMarketplace.connect(signers[1]).setMechFactoryStatuses([AddressZero], [true])
            ).to.be.revertedWithCustomError(mechMarketplace, "OwnerOnly");
            await expect(
                mechMarketplace.connect(signers[1]).setPaymentTypeBalanceTrackers([ethers.constants.HashZero], [AddressZero])
            ).to.be.revertedWithCustomError(mechMarketplace, "OwnerOnly");

            // Wrong array lengths
            await expect(
                mechMarketplace.setMechFactoryStatuses([AddressZero], [])
            ).to.be.revertedWithCustomError(mechMarketplace, "WrongArrayLength");
            await expect(
                mechMarketplace.setPaymentTypeBalanceTrackers([paymentTypeHash], [])
            ).to.be.revertedWithCustomError(mechMarketplace, "WrongArrayLength");

            // Zero addresses
            await expect(
                mechMarketplace.setMechFactoryStatuses([AddressZero], [true])
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroAddress");
            await expect(
                mechMarketplace.setPaymentTypeBalanceTrackers([paymentTypeHash], [AddressZero])
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroAddress");
            // Zero value
            await expect(
                mechMarketplace.setPaymentTypeBalanceTrackers([ethers.constants.HashZero], [deployer.address])
            ).to.be.revertedWithCustomError(mechMarketplace, "ZeroValue");
        });
    });

    context("Request checks", async function () {
        it("Check mech and requester", async function () {
            // Mech that was not registered by the whitelisted factory
            await expect(
                mechMarketplace.checkMech(deployer.address)
            ).to.be.reverted;

            // Mech that has a different service Id
            await expect(
                mechMarketplace.checkRequester(deployer.address, requesterServiceId)
            ).to.be.revertedWithCustomError(mechMarketplace, "OwnerOnly");

        });
    });
});
