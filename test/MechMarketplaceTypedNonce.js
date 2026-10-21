/*global describe, it*/

const {expect} = require("chai");
const {config, ethers} = require("hardhat");
const {RATE, FUNDS, fixture, settleSigned, state} = require("./helpers/deliveryPayload");

const TYPES = {ExplicitNonceDelivery: [
    {name: "mech", type: "address"},
    {name: "requester", type: "address"},
    {name: "data", type: "bytes"},
    {name: "maxDeliveryRate", type: "uint256"},
    {name: "paymentType", type: "bytes32"},
    {name: "nonce", type: "uint256"},
    {name: "deadline", type: "uint256"}
]};
const OLD_NONCE_CALL = "deliverMarketplaceWithSignatures(address,(bytes,bytes,bytes)[],uint256[],uint256[],uint256[],bytes)";

async function authorization(f, options = {}) {
    const account = options.account || f.requester.address;
    const deadline = options.deadline === undefined
        ? (await ethers.provider.getBlock("latest")).timestamp + 3600 : options.deadline;
    const domain = {name: "MechMarketplace", version: "2",
        chainId: (await ethers.provider.getNetwork()).chainId, verifyingContract: f.marketplace.address};
    const message = {mech: f.mech.address, requester: account, data: options.data || "0x1234",
        maxDeliveryRate: RATE, paymentType: f.paymentType,
        nonce: options.nonce === undefined ? 77 : options.nonce, deadline};
    const id = ethers.utils._TypedDataEncoder.hash(domain, TYPES, message);
    const signature = await f.wallet._signTypedData({...domain, ...options.domain}, TYPES,
        {...message, ...options.message});
    return {account, domain, message, ids: [id],
        items: [{requestData: message.data, deliveryData: "0xabcd", signature}],
        caps: [RATE], rates: [RATE], nonces: [message.nonce], deadlines: [deadline]};
}

async function fund(f, account) {
    if (f.token) {
        await f.token.mint(f.operator.address, FUNDS);
        await f.token.approve(f.tracker.address, FUNDS);
        await f.tracker.depositFor(account, FUNDS);
    } else await f.tracker.depositFor(account, {value: FUNDS});
}

async function walletFixture(kind) {
    const f = await fixture(kind);
    const Factory = await ethers.getContractFactory("MockTypedDataWallet");
    const wallet = await Factory.deploy();
    await wallet.deployed();
    await fund(f, wallet.address);
    const batch = await authorization(f, {account: wallet.address});
    batch.items[0].signature = "0x11223344";
    await wallet.configure(batch.ids[0], batch.items[0].signature, 0);
    return {f, wallet, batch};
}

function combine(first, second) {
    const batch = {account: first.account};
    for (const key of ["items", "ids", "caps", "rates", "nonces", "deadlines"]) {
        batch[key] = [...first[key], ...second[key]];
    }
    return batch;
}

async function deployArtifact(f, relative, ...args) {
    const artifact = require("@gnosis.pm/safe-contracts/build/artifacts/contracts/" + relative + ".json");
    const Factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, f.operator);
    const contract = await Factory.deploy(...args);
    await contract.deployed();
    return contract;
}

describe("Explicit-nonce EIP-712 signatures and deadlines", function () {
    it("matches standard domain and message encoding independently, including dynamic bytes", async function () {
        const f = await fixture();
        const legacyDomain = await f.marketplace.getDomainSeparator();
        for (const size of [0, 1, 31, 32, 33, 200]) {
            const data = "0x" + "ab".repeat(size);
            const b = await authorization(f, {data, nonce: ethers.constants.MaxUint256,
                deadline: ethers.constants.MaxUint256});
            expect(await f.marketplace.getDomainSeparatorWithNonce())
                .to.equal(ethers.utils._TypedDataEncoder.hashDomain(b.domain));
            expect(await f.marketplace.getRequestIdWithNonce(f.mech.address, b.account, data,
                RATE, f.paymentType, b.nonces[0], b.deadlines[0])).to.equal(b.ids[0]);
        }
        expect(await f.marketplace.getDomainSeparator()).to.equal(legacyDomain);
        expect(await f.marketplace.getDomainSeparatorWithNonce()).not.to.equal(legacyDomain);
    });

    for (const kind of ["Native", "Token"]) {
        it(kind + ": accepts standard typed-data EOA signatures and prevents exact-request replay", async function () {
            const f = await fixture(kind);
            const b = await authorization(f);
            b.rates[0] = RATE - 1;
            await settleSigned(f, 2, b);
            expect(await f.marketplace.getRequestStatus(b.ids[0])).to.equal(3);
            expect(await f.marketplace.mapNonces(b.account)).to.equal(0);
            expect(await f.tracker.mapMechBalances(f.mech.address)).to.equal(RATE - 1);
            const before = await state(f, b.ids);
            await expect(settleSigned(f, 2, b)).to.be.revertedWithCustomError(f.marketplace, "AlreadyRequested");
            expect(await state(f, b.ids)).to.equal(before);
        });

        it(kind + ": passes an opaque ERC-1271 signature unchanged to its wallet", async function () {
            const {f, wallet, batch} = await walletFixture(kind);
            await wallet.configure(batch.ids[0], "0xffff", 0);
            const before = await state(f, batch.ids, wallet.address);
            await expect(settleSigned(f, 2, batch))
                .to.be.revertedWithCustomError(f.marketplace, "SignatureNotValidated");
            expect(await state(f, batch.ids, wallet.address)).to.equal(before);
            await wallet.configure(batch.ids[0], batch.items[0].signature, 0);
            await settleSigned(f, 2, batch);
            expect(await f.tracker.mapMechBalances(f.mech.address)).to.equal(RATE);
        });

        for (const mode of [1, 2, 3]) {
            it(kind + ": rejects ERC-1271 wrong magic, revert or malformed response mode " + mode, async function () {
                const {f, wallet, batch} = await walletFixture(kind);
                await wallet.configure(batch.ids[0], batch.items[0].signature, mode);
                const before = await state(f, batch.ids, wallet.address);
                await expect(settleSigned(f, 2, batch)).to.be.reverted;
                expect(await state(f, batch.ids, wallet.address)).to.equal(before);
            });
        }

        it(kind + ": enforces expiry even when the ERC-1271 wallet approves the digest", async function () {
            const {f, wallet, batch} = await walletFixture(kind);
            expect(await wallet.isValidSignature(batch.ids[0], batch.items[0].signature)).to.equal("0x1626ba7e");
            const before = await state(f, batch.ids, wallet.address);
            await ethers.provider.send("evm_setNextBlockTimestamp", [batch.deadlines[0] + 1]);
            await expect(settleSigned(f, 2, batch)).to.be.revertedWithCustomError(f.marketplace, "SignatureExpired");
            expect(await state(f, batch.ids, wallet.address)).to.equal(before);
        });

        it(kind + ": validates actual 2-of-2 Safe signatures through its compatibility handler", async function () {
            const f = await fixture(kind);
            const singleton = await deployArtifact(f, "GnosisSafe.sol/GnosisSafe");
            const proxy = await deployArtifact(f, "proxies/GnosisSafeProxy.sol/GnosisSafeProxy", singleton.address);
            const handler = await deployArtifact(f, "handler/CompatibilityFallbackHandler.sol/CompatibilityFallbackHandler");
            const safe = singleton.attach(proxy.address);
            const accounts = config.networks.hardhat.accounts;
            const operatorWallet = ethers.Wallet.fromMnemonic(accounts.mnemonic, accounts.path + "/0");
            const owners = [operatorWallet, f.wallet].sort((a, b) =>
                a.address.toLowerCase().localeCompare(b.address.toLowerCase()));
            await safe.setup(owners.map((w) => w.address), 2, ethers.constants.AddressZero, "0x",
                handler.address, ethers.constants.AddressZero, 0, ethers.constants.AddressZero);
            await fund(f, safe.address);
            const b = await authorization(f, {account: safe.address});
            const safeHash = await handler.getMessageHashForSafe(safe.address,
                ethers.utils.defaultAbiCoder.encode(["bytes32"], [b.ids[0]]));
            const signatures = owners.map((w) => ethers.utils.joinSignature(w._signingKey().signDigest(safeHash)));
            b.items[0].signature = signatures[0];
            const before = await state(f, b.ids, safe.address);
            await expect(settleSigned(f, 2, b)).to.be.reverted;
            expect(await state(f, b.ids, safe.address)).to.equal(before);
            b.items[0].signature = ethers.utils.hexConcat(signatures);
            expect(ethers.utils.arrayify(b.items[0].signature).length).to.equal(130);
            await settleSigned(f, 2, b);
            expect(await f.marketplace.getRequestStatus(b.ids[0])).to.equal(3);
            expect(await f.tracker.mapMechBalances(f.mech.address)).to.equal(RATE);
        });
    }

    for (const delta of [-1, 0, 1]) {
        it("EOA deadline boundary: timestamp minus deadline = " + delta, async function () {
            const f = await fixture();
            const b = await authorization(f);
            const before = await state(f, b.ids);
            await ethers.provider.send("evm_setNextBlockTimestamp", [b.deadlines[0] + delta]);
            if (delta > 0) {
                await expect(settleSigned(f, 2, b)).to.be.revertedWithCustomError(f.marketplace, "SignatureExpired")
                    .withArgs(b.deadlines[0], b.deadlines[0] + delta);
                expect(await state(f, b.ids)).to.equal(before);
            } else {
                await settleSigned(f, 2, b);
                expect(await f.marketplace.getRequestStatus(b.ids[0])).to.equal(3);
            }
        });
    }

    it("treats deadline zero as expired rather than as a no-expiry sentinel", async function () {
        const f = await fixture();
        const b = await authorization(f, {deadline: 0});
        const before = await state(f, b.ids);
        await expect(settleSigned(f, 2, b)).to.be.revertedWithCustomError(f.marketplace, "SignatureExpired");
        expect(await state(f, b.ids)).to.equal(before);
    });

    for (const field of ["mech", "requester", "data", "maxDeliveryRate", "paymentType", "nonce", "deadline",
        "chainId", "version", "verifyingContract"]) {
        it("rejects a signature with a different signed " + field, async function () {
            const f = await fixture();
            const b = await authorization(f);
            const messageChanges = {mech: f.operator.address, requester: f.operator.address, data: "0x99",
                maxDeliveryRate: RATE + 1, paymentType: ethers.constants.HashZero, nonce: 78,
                deadline: b.deadlines[0] + 1};
            const domainChanges = {chainId: b.domain.chainId + 1, version: "1", verifyingContract: f.operator.address};
            b.items[0].signature = await f.wallet._signTypedData(
                {...b.domain, ...(field in domainChanges ? {[field]: domainChanges[field]} : {})}, TYPES,
                {...b.message, ...(field in messageChanges ? {[field]: messageChanges[field]} : {})});
            const before = await state(f, b.ids);
            await expect(settleSigned(f, 2, b)).to.be.revertedWithCustomError(f.marketplace, "SignatureNotValidated");
            expect(await state(f, b.ids)).to.equal(before);
        });
    }

    it("rejects personal-sign signatures and replay between legacy and typed-data paths", async function () {
        const f = await fixture();
        const b = await authorization(f);
        b.items[0].signature = await f.wallet.signMessage(ethers.utils.arrayify(b.ids[0]));
        await expect(settleSigned(f, 2, b)).to.be.revertedWithCustomError(f.marketplace, "SignatureNotValidated");
        const legacy = await f.marketplace.getRequestId(f.mech.address, b.account, b.message.data,
            RATE, f.paymentType, b.nonces[0]);
        b.items[0].signature = ethers.utils.joinSignature(f.wallet._signingKey().signDigest(legacy));
        await expect(settleSigned(f, 2, b)).to.be.revertedWithCustomError(f.marketplace, "SignatureNotValidated");
        const typed = await authorization(f, {nonce: 0});
        await expect(settleSigned(f, 0, typed)).to.be.revertedWithCustomError(f.marketplace, "SignatureNotValidated");
        await expect(settleSigned(f, 1, typed)).to.be.revertedWithCustomError(f.marketplace, "SignatureNotValidated");
    });

    it("retires the old no-deadline selector and rejects old custom-format authorizations", async function () {
        const f = await fixture();
        const b = await authorization(f);
        const oldHash = ethers.utils.keccak256(ethers.utils.solidityPack(["bytes2", "bytes32", "bytes32"],
            ["0x1901", await f.marketplace.getDomainSeparator(),
                ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
                    ["bytes32", "address", "address", "address", "bytes32", "uint256", "bytes32", "uint256"],
                    [ethers.utils.id("ExplicitNonceDelivery"), f.marketplace.address, f.mech.address, b.account,
                        ethers.utils.keccak256(b.message.data), RATE, f.paymentType, b.nonces[0]]))]));
        b.items[0].signature = ethers.utils.joinSignature(f.wallet._signingKey().signDigest(oldHash));
        await expect(settleSigned(f, 2, b)).to.be.revertedWithCustomError(f.marketplace, "SignatureNotValidated");
        expect(f.marketplace.interface.functions[OLD_NONCE_CALL]).to.equal(undefined);
        expect(f.mech.interface.functions[OLD_NONCE_CALL]).to.equal(undefined);
        const oldInterface = new ethers.utils.Interface(["function " + OLD_NONCE_CALL]);
        const data = oldInterface.encodeFunctionData(OLD_NONCE_CALL,
            [b.account, b.items.map((item) => [item.requestData, item.signature, item.deliveryData]),
                b.rates, b.caps, b.nonces, "0x"]);
        await expect(f.operator.sendTransaction({to: f.mech.address, data})).to.be.reverted;
        await ethers.provider.send("hardhat_impersonateAccount", [f.mech.address]);
        await ethers.provider.send("hardhat_setBalance", [f.mech.address, "0x1000000000000000000"]);
        try {
            await expect((await ethers.getSigner(f.mech.address)).sendTransaction({to: f.marketplace.address, data}))
                .to.be.reverted;
        } finally {
            await ethers.provider.send("hardhat_stopImpersonatingAccount", [f.mech.address]);
        }
    });

    it("rejects missing deadlines and rolls back a batch with an expired second authorization", async function () {
        const f = await fixture();
        const first = await authorization(f);
        const second = await authorization(f, {nonce: 78,
            deadline: (await ethers.provider.getBlock("latest")).timestamp - 1});
        const b = combine(first, second);
        expect(ethers.utils.recoverAddress(second.ids[0], second.items[0].signature)).to.equal(f.requester.address);
        const before = await state(f, b.ids);
        await expect(settleSigned(f, 2, {...b, deadlines: []}))
            .to.be.revertedWithCustomError(f.marketplace, "WrongArrayLength").withArgs(2, 0);
        await expect(settleSigned(f, 2, b)).to.be.revertedWithCustomError(f.marketplace, "SignatureExpired");
        expect(await state(f, b.ids)).to.equal(before);
        await settleSigned(f, 2, combine(first, await authorization(f, {nonce: 78})));
        expect(await f.tracker.mapMechBalances(f.mech.address)).to.equal(RATE * 2);
    });
});
