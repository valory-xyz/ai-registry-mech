/*global describe, it*/

const {expect} = require("chai");
const {ethers, network} = require("hardhat");

const RATE = 100;
const SERVICE = 1;
const PAYLOAD = ethers.utils.defaultAbiCoder.encode(["uint256"], [RATE]);

async function deploy(name, ...args) {
    const Factory = await ethers.getContractFactory(name);
    const instance = await Factory.deploy(...args);
    await instance.deployed();
    return instance;
}

async function fixture(kind) {
    const [owner] = await ethers.getSigners();
    const registry = await deploy("MockServiceRegistry");
    await registry.setServiceOwner(SERVICE, owner.address);
    const karma = await deploy("Karma");
    const implementation = await deploy("MechMarketplace", registry.address, karma.address);
    const proxy = await deploy("MechMarketplaceProxy", implementation.address,
        implementation.interface.encodeFunctionData("initialize", [100, 10, 20]));
    const marketplace = implementation.attach(proxy.address);
    const factory = await deploy("MechFactoryFixedPrice" + kind, marketplace.address);
    await marketplace.setMechFactoryStatuses([factory.address], [true]);
    const asset = await deploy(kind === "Native" ? "WETH9" : "ERC20Token");
    const tracker = await deploy("BalanceTrackerFixedPrice" + kind,
        marketplace.address, owner.address, asset.address);
    return {kind, registry, marketplace, factory, tracker, paymentType: ethers.utils.id("FixedPrice" + kind)};
}

async function predictedMech(f, timestamp, nonce) {
    const Factory = await ethers.getContractFactory("MechFixedPrice" + f.kind);
    const creationCode = Factory.getDeployTransaction(f.marketplace.address, f.registry.address, SERVICE, RATE).data;
    const salt = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
        ["uint256", "bytes", "uint256", "uint256"], [timestamp, PAYLOAD, SERVICE, nonce]));
    return ethers.utils.getCreate2Address(f.factory.address, salt, ethers.utils.keccak256(creationCode));
}

describe("Marketplace creation requires a configured payment tracker", function () {
    for (const kind of ["Native", "Token"]) {
        it(kind + ": rejects missing tracker, rolls back mech deployment and can retry", async function () {
            const f = await fixture(kind);
            const timestamp = (await ethers.provider.getBlock("latest")).timestamp + 10;
            const rejectedAddress = await predictedMech(f, timestamp, 0);
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            // Explicit gas limit mines the reverted transaction, making deployment rollback observable.
            await expect(f.marketplace.create(SERVICE, f.factory.address, PAYLOAD, {gasLimit: 6000000}))
                .to.be.revertedWithCustomError(f.marketplace, "ZeroAddress");
            expect(await ethers.provider.getCode(rejectedAddress)).to.equal("0x");
            expect(await f.marketplace.mapAgentMechFactories(rejectedAddress)).to.equal(ethers.constants.AddressZero);
            expect(await f.marketplace.numMechs()).to.equal(0);
            const failedBlock = await ethers.provider.getBlockNumber();
            expect(await f.marketplace.queryFilter(f.marketplace.filters.CreateMech(), failedBlock, failedBlock))
                .to.have.length(0);
            const factoryEvent = "CreateMechFixedPrice" + kind;
            expect(await f.factory.queryFilter(f.factory.filters[factoryEvent](), failedBlock, failedBlock))
                .to.have.length(0);

            await f.marketplace.setPaymentTypeBalanceTrackers([f.paymentType], [f.tracker.address]);
            const retryTimestamp = (await ethers.provider.getBlock("latest")).timestamp + 10;
            // The retry must use factory nonce zero again: the failed creation must not consume it.
            const expected = await predictedMech(f, retryTimestamp, 0);
            await network.provider.send("evm_setNextBlockTimestamp", [retryTimestamp]);
            await expect(f.marketplace.create(SERVICE, f.factory.address, PAYLOAD))
                .to.emit(f.marketplace, "CreateMech").withArgs(expected, SERVICE, f.factory.address);
            expect(await ethers.provider.getCode(expected)).not.to.equal("0x");
            expect(await f.marketplace.mapAgentMechFactories(expected)).to.equal(f.factory.address);
            expect(await f.marketplace.numMechs()).to.equal(1);
            const mech = await ethers.getContractAt("MechFixedPrice" + kind, expected);
            expect(await mech.paymentType()).to.equal(f.paymentType);
            expect(await f.marketplace.checkMech(expected)).to.equal(await f.registry.ownerOf(SERVICE));
        });

        it(kind + ": a tracker configured for another payment type does not permit creation", async function () {
            const f = await fixture(kind);
            const otherType = ethers.utils.id("UnrelatedPaymentType");
            await f.marketplace.setPaymentTypeBalanceTrackers([otherType], [f.tracker.address]);
            expect(await f.marketplace.mapPaymentTypeBalanceTrackers(otherType)).to.equal(f.tracker.address);
            expect(await f.marketplace.mapPaymentTypeBalanceTrackers(f.paymentType)).to.equal(ethers.constants.AddressZero);
            await expect(f.marketplace.create(SERVICE, f.factory.address, PAYLOAD))
                .to.be.revertedWithCustomError(f.marketplace, "ZeroAddress");
            expect(await f.marketplace.numMechs()).to.equal(0);
        });
    }
});
