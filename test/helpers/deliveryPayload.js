/*global __dirname*/

const fs = require("fs");
const path = require("path");
const { config, ethers } = require("hardhat");

const RATE = 100;
const FUNDS = 10000;
const SIGNED = [
    "deliverMarketplaceWithSignatures(address,(bytes,bytes,bytes)[],uint256[],bytes)",
    "deliverMarketplaceWithSignatures(address,(bytes,bytes,bytes)[],uint256[],uint256[],bytes)",
    "deliverMarketplaceWithSignatures(address,(bytes,bytes,bytes)[],uint256[],uint256[],uint256[],uint256[],bytes)"
];

async function deploy(name, ...args) {
    const Factory = await ethers.getContractFactory(name);
    const contract = await Factory.deploy(...args);
    await contract.deployed();
    return contract;
}

async function fixture(kind = "Native", factoryName) {
    const [operator, requester] = await ethers.getSigners();
    const registry = await deploy("MockServiceRegistry");
    const karma = await deploy("Karma");
    await karma.initialize();
    const implementation = await deploy("MechMarketplace", registry.address, karma.address);
    const proxy = await deploy("MechMarketplaceProxy", implementation.address,
        implementation.interface.encodeFunctionData("initialize", [100, 10, 20]));
    const marketplace = implementation.attach(proxy.address);
    await karma.setMechMarketplaceStatuses([marketplace.address], [true]);
    const factory = await deploy(factoryName || "MechFactoryFixedPrice" + kind, marketplace.address);
    await marketplace.setMechFactoryStatuses([factory.address], [true]);
    await registry.setServiceOwner(1, operator.address);
    const token = kind === "Token" ? await deploy("ERC20Token") : undefined;
    const tracker = await deploy("BalanceTrackerFixedPrice" + kind, marketplace.address,
        operator.address, token ? token.address : operator.address);
    const paymentType = ethers.utils.id("FixedPrice" + kind);
    await marketplace.setPaymentTypeBalanceTrackers([paymentType], [tracker.address]);
    const creation = await (await marketplace.create(1, factory.address,
        ethers.utils.defaultAbiCoder.encode(["uint256"], [RATE]))).wait();
    const mechAddress = creation.events.find((event) => event.event === "CreateMech").args.mech;
    const mech = await ethers.getContractAt("MechFixedPrice" + kind, mechAddress);
    const contractRequester = await deploy("MockOperatorContract");
    if (token) {
        await token.mint(operator.address, FUNDS * 2);
        await token.approve(tracker.address, FUNDS * 2);
        await tracker.depositFor(requester.address, FUNDS);
        await tracker.depositFor(contractRequester.address, FUNDS);
    } else {
        await tracker.depositFor(requester.address, { value: FUNDS });
        await tracker.depositFor(contractRequester.address, { value: FUNDS });
    }
    const accounts = config.networks.hardhat.accounts;
    const wallet = ethers.Wallet.fromMnemonic(accounts.mnemonic, accounts.path + "/1");
    if (wallet.address !== requester.address) throw new Error("requester key does not match fixture signer");
    return { kind, operator, requester, contractRequester, registry, karma, marketplace, mech,
        tracker, token, paymentType, wallet };
}

async function signedBatch(f, overload, account = f.requester.address, count = 2) {
    const nonce = await f.marketplace.mapNonces(account);
    const items = [];
    const ids = [];
    const nonces = [];
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 3600;
    const deadlines = Array(count).fill(deadline);
    for (let i = 0; i < count; ++i) {
        const requestData = ethers.utils.hexlify(ethers.utils.toUtf8Bytes("request " + overload + " " + i));
        const n = overload === 2 ? 1000 + i : nonce.add(i);
        const getter = overload === 2 ? "getRequestIdWithNonce" : "getRequestId";
        const args = [f.mech.address, account, requestData, RATE, f.paymentType, n];
        if (overload === 2) args.push(deadline);
        const id = await f.marketplace[getter](...args);
        let signature = "0x";
        if (account === f.contractRequester.address) await f.contractRequester.approveHash(id);
        else signature = ethers.utils.joinSignature(f.wallet._signingKey().signDigest(id));
        ids.push(id);
        nonces.push(n);
        items.push({ requestData, deliveryData: "0xabcd", signature });
    }
    return { account, items, ids, nonces, deadlines, rates: Array(count).fill(RATE), caps: Array(count).fill(RATE) };
}

function settleSigned(f, overload, batch) {
    const args = [batch.account, batch.items, batch.rates];
    if (overload > 0) args.push(batch.caps);
    if (overload === 2) args.push(batch.nonces, batch.deadlines);
    return f.mech[SIGNED[overload]](...args, "0x");
}

async function request(f, count = 1) {
    const ids = [];
    for (let i = 0; i < count; ++i) {
        const data = ethers.utils.hexlify(ethers.utils.toUtf8Bytes("ordinary request " + i));
        const nonce = await f.marketplace.mapNonces(f.requester.address);
        ids.push(await f.marketplace.getRequestId(f.mech.address, f.requester.address,
            data, RATE, f.paymentType, nonce));
        await f.marketplace.connect(f.requester).request(data, RATE, f.paymentType, f.mech.address, 10, "0x");
    }
    return ids;
}

async function state(f, ids, account = f.requester.address) {
    const values = await Promise.all([
        f.tracker.mapRequesterBalances(account), f.tracker.mapMechBalances(f.mech.address),
        f.tracker.collectedFees(), f.marketplace.mapNonces(account),
        f.marketplace.mapRequestCounts(account), f.marketplace.mapDeliveryCounts(account),
        f.marketplace.mapMechDeliveryCounts(f.mech.address),
        f.marketplace.mapMechServiceDeliveryCounts(f.operator.address),
        f.marketplace.numTotalRequests(), f.marketplace.numUndeliveredRequests(),
        f.mech.numTotalRequests(), f.mech.numTotalDeliveries(), f.mech.numUndeliveredRequests(),
        f.mech.getUndeliveredRequestIds(0, 0), f.karma.mapMechKarma(f.mech.address),
        f.karma.mapRequesterMechKarma(account, f.mech.address),
        ...ids.map((id) => f.marketplace.mapRequestIdInfos(id)),
        ...ids.map((id) => f.marketplace.getRequestStatus(id)),
        ...(f.token ? [f.token.balanceOf(f.tracker.address), f.token.balanceOf(account)]
            : [ethers.provider.getBalance(f.tracker.address), ethers.provider.getBalance(account)])
    ]);
    return JSON.stringify(values);
}

async function legacyMech(f) {
    const file = path.join(__dirname, "../../abis/0.8.28/MechFactoryFixedPriceNative.json");
    const artifact = JSON.parse(fs.readFileSync(file, "utf8"));
    const bytecode = typeof artifact.bytecode === "string" ? artifact.bytecode : artifact.bytecode.object;
    const Factory = new ethers.ContractFactory(artifact.abi,
        bytecode.startsWith("0x") ? bytecode : "0x" + bytecode, f.operator);
    const factory = await Factory.deploy(f.marketplace.address);
    await factory.deployed();
    await f.marketplace.setMechFactoryStatuses([factory.address], [true]);
    await f.registry.setServiceOwner(2, f.operator.address);
    const receipt = await (await f.marketplace.create(2, factory.address,
        ethers.utils.defaultAbiCoder.encode(["uint256"], [RATE]))).wait();
    const address = receipt.events.find((event) => event.event === "CreateMech").args.mech;
    return { ...f, mech: await ethers.getContractAt("MechFixedPriceNative", address) };
}

module.exports = { RATE, FUNDS, fixture, signedBatch, settleSigned, request, state, legacyMech };
