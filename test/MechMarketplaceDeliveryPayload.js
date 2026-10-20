/*global describe, it*/

const { expect } = require("chai");
const { RATE, FUNDS, fixture, signedBatch, settleSigned, request, state, legacyMech } = require("./helpers/deliveryPayload");

describe("Delivery payload validation", function () {
    for (const kind of ["Native", "Token"]) {
        describe(kind, function () {
            for (const contractAccount of [false, true]) {
                for (let overload = 0; overload < 3; ++overload) {
                    it("rejects an empty response atomically on signed path " + overload +
                        (contractAccount ? " with EIP-1271" : " with EOA"), async function () {
                        const f = await fixture(kind);
                        const account = contractAccount ? f.contractRequester.address : f.requester.address;
                        const batch = await signedBatch(f, overload, account);
                        // The second item fails after the first was processed: all effects must roll back.
                        batch.items[1].deliveryData = "0x";
                        const before = await state(f, batch.ids, account);
                        await expect(settleSigned(f, overload, batch)).to.be.revertedWithCustomError(f.marketplace, "ZeroValue");
                        expect(await state(f, batch.ids, account)).to.equal(before);
                        batch.items[1].deliveryData = "0x00";
                        // Zero actual charges remain supported by the cap paths when another item pays.
                        if (overload > 0) batch.rates[0] = 0;
                        await settleSigned(f, overload, batch);
                        const total = overload === 0 ? RATE * 2 : RATE;
                        expect(await f.tracker.mapMechBalances(f.mech.address)).to.equal(total);
                        expect(await f.tracker.mapRequesterBalances(account)).to.equal(FUNDS - total);
                        expect(await f.marketplace.mapNonces(account)).to.equal(overload === 2 ? 0 : 2);
                        expect(await f.marketplace.mapDeliveryCounts(account)).to.equal(2);
                        for (const id of batch.ids) expect(await f.marketplace.getRequestStatus(id)).to.equal(3);
                        if (overload === 2) {
                            await expect(settleSigned(f, overload, batch))
                                .to.be.revertedWithCustomError(f.marketplace, "AlreadyRequested");
                        }
                    });
                }
            }

            it("rejects an empty ordinary response without changing request or payment state", async function () {
                const f = await fixture(kind);
                expect(await f.mech.VERSION()).to.equal("1.1.0");
                const ids = await request(f);
                const before = await state(f, ids);
                await expect(f.mech.deliverToMarketplace(ids, ["0x"]))
                    .to.be.revertedWithCustomError(f.mech, "ZeroValue");
                expect(await state(f, ids)).to.equal(before);
                await expect(f.mech.deliverToMarketplace(ids, ["0x00"]))
                    .to.emit(f.mech, "Deliver").withArgs(f.mech.address, f.operator.address, ids[0], RATE, "0x00");
                expect(await f.marketplace.getRequestStatus(ids[0])).to.equal(3);
                expect(await f.tracker.mapMechBalances(f.mech.address)).to.equal(RATE);
            });

            it("rolls back a mixed ordinary batch, then settles a valid batch once", async function () {
                const f = await fixture(kind);
                const ids = await request(f, 2);
                const before = await state(f, ids);
                await expect(f.mech.deliverToMarketplace(ids, ["0xab", "0x"]))
                    .to.be.revertedWithCustomError(f.mech, "ZeroValue");
                expect(await state(f, ids)).to.equal(before);
                await f.mech.deliverToMarketplace(ids, ["0xab", "0xcd"]);
                expect(await f.mech.numUndeliveredRequests()).to.equal(0);
                expect(await f.marketplace.numUndeliveredRequests()).to.equal(0);
                expect(await f.tracker.mapMechBalances(f.mech.address)).to.equal(RATE * 2);
                const delivered = await state(f, ids);
                await f.mech.deliverToMarketplace(ids, ["0xab", "0xcd"]);
                expect(await state(f, ids)).to.equal(delivered);
            });
        });
    }

    it("validates processed output even when the supplied input is nonempty", async function () {
        const f = await fixture("Native", "MechFactoryEmptyProcessedDelivery");
        const ids = await request(f);
        const before = await state(f, ids);
        await expect(f.mech.deliverToMarketplace(ids, ["0xab"]))
            .to.be.revertedWithCustomError(f.mech, "ZeroValue");
        expect(await state(f, ids)).to.equal(before);
    });

    it("retains ordinary delivery compatibility for a mech created by the legacy factory artifact", async function () {
        const f = await legacyMech(await fixture());
        const ids = await request(f);
        await f.mech.deliverToMarketplace(ids, ["0xabcd"]);
        expect(await f.marketplace.getRequestStatus(ids[0])).to.equal(3);
        expect(await f.tracker.mapMechBalances(f.mech.address)).to.equal(RATE);
    });
});
