/*global describe, it*/

const {expect} = require("chai");
const {ethers} = require("hardhat");

const SIGNED = [
    "deliverMarketplaceWithSignatures(address,(bytes,bytes,bytes)[],uint256[],bytes)",
    "deliverMarketplaceWithSignatures(address,(bytes,bytes,bytes)[],uint256[],uint256[],bytes)",
    "deliverMarketplaceWithSignatures(address,(bytes,bytes,bytes)[],uint256[],uint256[],uint256[],uint256[],bytes)"
];
const PATHS = ["ordinary", "signed rate", "signed cap", "signed explicit nonce"];
const IDS = [ethers.utils.id("outer request"), ethers.utils.id("inner request")];

async function deploy(name, ...args) {
    const Factory = await ethers.getContractFactory(name);
    const instance = await Factory.deploy(...args);
    await instance.deployed();
    return instance;
}

async function fixture() {
    const [controller, requester] = await ethers.getSigners();
    const marketplace = await deploy("MockCallbackMarketplace");
    const operator = await deploy("MockDeliveryOperator", marketplace.address);
    const registry = await deploy("MockServiceRegistry");
    await registry.setServiceOwner(1, operator.address);
    const mech = await deploy("MechFixedPriceNative", marketplace.address, registry.address, 1, 100);
    await marketplace.queue(mech.address, IDS, ["0x1234", "0x5678"]);
    return {controller, requester, marketplace, operator, registry, mech};
}

function delivery(f, path, id = IDS[0]) {
    if (path === 0) return f.mech.interface.encodeFunctionData("deliverToMarketplace", [[id], ["0xabcd"]]);
    // The callback mock deliberately does not validate signatures. These tests isolate the mech guard.
    const args = [f.requester.address, [{requestData: "0x1234", deliveryData: "0xabcd", signature: "0x"}], [80]];
    if (path > 1) args.push([100]);
    if (path === 3) args.push([77], [ethers.constants.MaxUint256]);
    args.push("0x");
    return f.mech.interface.encodeFunctionData(SIGNED[path - 1], args);
}

describe("OlasMech shared delivery reentrancy lock", function () {
    for (let outer = 0; outer < PATHS.length; ++outer) {
        for (let inner = 0; inner < PATHS.length; ++inner) {
            it(PATHS[outer] + " blocks authorized re-entry into " + PATHS[inner], async function () {
                const f = await fixture();
                const nested = delivery(f, inner, IDS[1]);
                await f.marketplace.configure(f.operator.address, nested, false, false);
                const tx = await f.operator.execute(f.mech.address, [delivery(f, outer)]);
                if (outer > 0) {
                    await expect(tx).to.emit(f.mech, "NumRequestsIncrease").withArgs(1);
                }
                expect(await f.marketplace.callbackSucceeded()).to.equal(false);
                expect(await f.marketplace.callbackResult())
                    .to.equal(f.mech.interface.getSighash("ReentrancyGuard()"));
                expect(await f.marketplace.settlementCalls()).to.equal(1);
                expect(await f.mech.numTotalDeliveries()).to.equal(1);
                expect(await f.mech.numTotalRequests()).to.equal(2 + Number(outer > 0));
                expect(await f.mech.numUndeliveredRequests()).to.equal(outer === 0 ? 1 : 2);
                expect(await f.mech.getUndeliveredRequestIds(0, 0)).to.include(IDS[1]);

                // Positive control: the identical nested call is authorized and succeeds after the outer call.
                await f.operator.execute(f.mech.address, [nested]);
                expect(await f.marketplace.settlementCalls()).to.equal(2);
                expect(await f.mech.numTotalDeliveries()).to.equal(2);
                expect(await f.mech.numTotalRequests()).to.equal(2 + Number(outer > 0) + Number(inner > 0));
                expect(await f.mech.numUndeliveredRequests())
                    .to.equal(2 - Number(outer === 0) - Number(inner === 0));
            });
        }
    }

    for (let path = 1; path < PATHS.length; ++path) {
        it(PATHS[path] + " rolls back a propagated callback failure and can retry", async function () {
            const f = await fixture();
            const call = delivery(f, path);
            await f.marketplace.configure(f.operator.address, call, true, false);
            await expect(f.operator.execute(f.mech.address, [call]))
                .to.be.revertedWithCustomError(f.mech, "ReentrancyGuard");
            expect(await f.marketplace.settlementCalls()).to.equal(0);
            expect(await f.mech.numTotalRequests()).to.equal(2);
            expect(await f.mech.numTotalDeliveries()).to.equal(0);
            expect(await f.mech.numUndeliveredRequests()).to.equal(2);
            await f.marketplace.configure(f.operator.address, "0x", false, false);
            await f.operator.execute(f.mech.address, [call]);
            expect(await f.mech.numTotalDeliveries()).to.equal(1);
        });

        it(PATHS[path] + " unlocks after a Marketplace revert and between calls in one transaction", async function () {
            const f = await fixture();
            const call = delivery(f, path);
            await f.marketplace.configure(f.operator.address, "0x", false, true);
            await expect(f.operator.execute(f.mech.address, [call]))
                .to.be.revertedWithCustomError(f.marketplace, "ForcedSettlementFailure");
            expect(await f.marketplace.settlementCalls()).to.equal(0);
            expect(await f.mech.numTotalRequests()).to.equal(2);
            expect(await f.mech.numTotalDeliveries()).to.equal(0);
            await f.marketplace.configure(f.operator.address, "0x", false, false);
            await f.operator.execute(f.mech.address, [call, call]);
            expect(await f.marketplace.settlementCalls()).to.equal(2);
            expect(await f.mech.numTotalRequests()).to.equal(4);
            expect(await f.mech.numTotalDeliveries()).to.equal(2);
        });
    }
});
