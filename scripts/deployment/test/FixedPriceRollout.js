/*global process, __dirname*/

// Local-only rehearsal of the actual shell entrypoints. Requires compiled Hardhat artifacts,
// anvil, cast, forge, jq and solc 0.8.30 (or FOUNDRY_SOLC pointing to that compiler).
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const net = require("net");
const {spawn, execFile} = require("child_process");
const {promisify} = require("util");
const {createRequire} = require("module");
const root = process.env.MARKETPLACE_SCRIPT_SOURCE || path.resolve(__dirname, "../../..");
const requireProject = createRequire(path.join(root, "package.json"));
const {ethers, artifacts} = requireProject("hardhat");
const execute = promisify(execFile);
const checks = [];

async function freePort() {
    const server = net.createServer();
    await new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(0, "127.0.0.1", resolve);
    });
    const port = server.address().port;
    await new Promise(resolve => server.close(resolve));
    return port;
}

function check(name, condition) {
    assert(condition, name);
    checks.push(name);
    console.log("PASS:", name);
}

async function main() {
    const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "marketplace-rollout-"));
    const port = await freePort();
    // No ambient credentials are passed to Anvil or the deployment commands.
    const cleanEnv = {PATH: process.env.PATH, HOME: process.env.HOME};
    if (process.env.FOUNDRY_SOLC) cleanEnv.FOUNDRY_SOLC = process.env.FOUNDRY_SOLC;
    const anvil = spawn("anvil", ["--silent", "--port", String(port), "--chain-id", "31337"],
        {env: cleanEnv, stdio: "ignore"});
    let startError;
    anvil.on("error", error => { startError = error; });
    try {
        const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:" + port);
        let connected = false;
        for (let attempt = 0; attempt < 100; ++attempt) {
            if (startError) throw startError;
            try {
                await provider.getBlockNumber();
                connected = true;
                break;
            } catch {
                await new Promise(resolve => setTimeout(resolve, 100));
            }
        }
        assert(connected, "Local Anvil did not start");
        // Ephemeral test wallet: no checked-in key or mnemonic, no live funds.
        const owner = ethers.Wallet.createRandom().connect(provider);
        const requester = ethers.Wallet.createRandom().connect(provider);
        await provider.send("anvil_setBalance", [owner.address, ethers.utils.hexValue(ethers.utils.parseEther("100"))]);
        const env = {...cleanEnv, PRIVATE_KEY: owner.privateKey};
        const deployment = path.join(temporary, "scripts/deployment");
        fs.mkdirSync(deployment, {recursive: true});
        fs.cpSync(path.join(root, "scripts/deployment/lib"), path.join(deployment, "lib"), {recursive: true});
        const names = [
            "deploy_03_mech_marketplace.sh", "deploy_04_mech_marketplace_proxy.sh",
            "deploy_05_mech_factory_fixed_price_native.sh", "deploy_07a_mech_factory_fixed_price_token_olas.sh",
            "deploy_07b_mech_factory_fixed_price_token_usdc.sh", "script_06_change_implementaion_mech_marketplace_proxy.sh",
            "script_02a_marketplace_set_factories_fixed.sh", "script_03a_marketplace_set_balance_trackers_fixed.sh"
        ];
        for (const name of names) fs.copyFileSync(path.join(root, "scripts/deployment", name), path.join(deployment, name));
        // Sources/dependencies are read through links; all compiler output and globals stay in the temporary directory.
        for (const name of ["contracts", "lib", "node_modules", "abis", "test", "foundry.toml"])
            fs.symlinkSync(path.join(root, name), path.join(temporary, name));
        // Proposal scripts are unrelated to this fixed-price rollout and are excluded by the entrypoints.
        let config;
        const globals = path.join(deployment, "globals_local.json");
        const save = () => fs.writeFileSync(globals, JSON.stringify(config, null, 2) + "\n");
        const run = async (name, ...args) => {
            const result = await execute("bash", [path.join(deployment, name), "local", ...args],
                {env, cwd: temporary, timeout: 180000, maxBuffer: 1024 * 1024});
            config = JSON.parse(fs.readFileSync(globals, "utf8"));
            return result.stdout;
        };
        const contract = async (name, address) => {
            return new ethers.Contract(ethers.utils.getAddress(address), (await artifacts.readArtifact(name)).abi, owner);
        };
        const deploy = async (name, ...args) => {
            const artifact = await artifacts.readArtifact(name);
            const value = await new ethers.ContractFactory(artifact.abi, artifact.bytecode, owner).deploy(...args);
            await value.deployed();
            return value;
        };
        const expectRejected = async (name, script, args, expectedError) => {
            const beforeConfig = fs.readFileSync(globals, "utf8");
            const beforeNonce = await owner.getTransactionCount("latest");
            let failure;
            try {
                await run(script, ...args);
            } catch (error) {
                failure = error;
            }
            check(name, failure && failure.stderr.includes(expectedError) && !failure.stdout.includes("Data:") &&
                await owner.getTransactionCount("latest") === beforeNonce &&
                fs.readFileSync(globals, "utf8") === beforeConfig);
        };
        const registry = await deploy("MockServiceRegistry");
        const karma = await deploy("Karma");
        await (await karma.initialize()).wait();
        const nativeAsset = await deploy("WETH9");
        const olas = await deploy("ERC20Token");
        const usdc = await deploy("ERC20Token");
        config = {contractVerification: false, useLedger: false, chainId: "31337",
            networkURL: "http://127.0.0.1:" + port, fee: "100", minResponseTimeout: "10", maxResponseTimeout: "20",
            serviceRegistryAddress: registry.address, karmaProxyAddress: karma.address,
            wrappedNativeTokenAddress: nativeAsset.address, olasAddress: olas.address, usdcAddress: usdc.address};
        save();
        await run("deploy_03_mech_marketplace.sh");
        let implementation = await contract("MechMarketplace", config.mechMarketplaceAddress);
        check("implementation deployment and version readback", await implementation.VERSION() === "1.2.0");
        const records = path.join(deployment, ".deployment-records", "globals_local");
        await expectRejected("a repeated deployment requires an explicit replacement",
            "deploy_03_mech_marketplace.sh", [], "Deployment already configured");
        // Simulate a transport failure after a real Forge deployment was mined.
        const wrapperBin = path.join(temporary, "wrapper-bin");
        fs.mkdirSync(wrapperBin);
        const realForge = cleanEnv.PATH.split(path.delimiter).map(directory => path.join(directory, "forge")).find(file => fs.existsSync(file));
        assert(realForge, "Missing real Forge executable");
        const wrapper = "#!/usr/bin/env node\n" +
            "const {spawnSync}=require('child_process');\n" +
            "const args=process.argv.slice(2);\n" +
            "if(args[0]==='create' && process.env.SIMULATE_DEPLOY_FAILURE==='before'){console.error('Simulated failure before broadcasting');process.exit(9);}\n" +
            "if(args[0]==='verify-contract' && process.env.SIMULATE_EXPLORER){if(process.env.SIMULATE_EXPLORER==='fail'){console.error('Simulated explorer failure api='+process.env.ETHERSCAN_API_KEY);process.exit(9);}process.exit(0);}\n" +
            "const result=spawnSync(" + JSON.stringify(realForge) + ",args,{encoding:'utf8'});\n" +
            "process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');\n" +
            "if(args[0]==='create' && result.status===0 && process.env.SIMULATE_DEPLOY_FAILURE==='after'){console.error('Receipt timeout at https://user:pass@example.invalid/api?key=hidden-url-secret private='+process.env.PRIVATE_KEY+' api='+process.env.ETHERSCAN_API_KEY);process.exit(9);}\n" +
            "process.exit(result.status===null?1:result.status);\n";
        fs.writeFileSync(path.join(wrapperBin, "forge"), wrapper, {mode: 0o755});
        env.PATH = wrapperBin + path.delimiter + cleanEnv.PATH;
        env.ETHERSCAN_API_KEY = "ephemeral-explorer-value";
        env.SIMULATE_DEPLOY_FAILURE = "after";
        const previousImplementation = implementation.address;
        const beforeFailureConfig = fs.readFileSync(globals, "utf8");
        const beforeFailureNonce = await owner.getTransactionCount("latest");
        let timedOut;
        try {
            await run("deploy_03_mech_marketplace.sh", "--replace", previousImplementation);
        } catch (error) {
            timedOut = error;
        }
        delete env.SIMULATE_DEPLOY_FAILURE;
        const pendingPath = path.join(records, "mechMarketplaceAddress.pending.json");
        const pending = JSON.parse(fs.readFileSync(pendingPath, "utf8"));
        check("a mined deployment timeout preserves the hash and old configuration",
            timedOut && timedOut.stderr.includes("Receipt timeout") && timedOut.stderr.includes(pending.transactionHash) &&
            await owner.getTransactionCount("latest") === beforeFailureNonce + 1 &&
            fs.readFileSync(globals, "utf8") === beforeFailureConfig);
        const diagnostics = timedOut.stderr + fs.readFileSync(pendingPath, "utf8");
        check("deployment diagnostics redact keys and credential-bearing URLs",
            ![owner.privateKey, owner.privateKey.slice(2), env.ETHERSCAN_API_KEY, "hidden-url-secret", "user:pass"]
                .some(secret => diagnostics.includes(secret)));
        await expectRejected("an unresolved attempt blocks the same deployment command",
            "deploy_03_mech_marketplace.sh", ["--replace", previousImplementation], "Unresolved deployment attempt exists");
        // Manual inspection is required: the script deliberately provides no adoption/retry command.
        const inspectedReceipt = await provider.getTransactionReceipt(pending.transactionHash);
        check("the retained transaction identifies the mined contract for manual inspection",
            inspectedReceipt.status === 1 && inspectedReceipt.contractAddress.toLowerCase() === pending.deployedTo.toLowerCase());
        // Archive only in this disposable test after inspecting the mined transaction.
        fs.renameSync(pendingPath, pendingPath + ".inspected");
        // A simulated explorer outage occurs after the deployment address is confirmed and saved.
        config.contractVerification = true;
        save();
        env.SIMULATE_EXPLORER = "fail";
        const beforeExplorerNonce = await owner.getTransactionCount("latest");
        let explorerFailure;
        try {
            await run("deploy_03_mech_marketplace.sh", "--replace", implementation.address);
        } catch (error) {
            explorerFailure = error;
        }
        config = JSON.parse(fs.readFileSync(globals, "utf8"));
        check("explorer failure retains the saved deployment and confirmed record",
            explorerFailure && explorerFailure.stderr.includes("Explorer verification failed") &&
            !explorerFailure.stderr.includes(env.ETHERSCAN_API_KEY) &&
            config.mechMarketplaceAddress.toLowerCase() !== implementation.address.toLowerCase() &&
            await owner.getTransactionCount("latest") === beforeExplorerNonce + 1 && !fs.existsSync(pendingPath));
        await expectRejected("explorer failure cannot trigger an accidental repeat deployment",
            "deploy_03_mech_marketplace.sh", [], "Deployment already configured");
        implementation = await contract("MechMarketplace", config.mechMarketplaceAddress);
        config.contractVerification = false;
        save();
        delete env.SIMULATE_EXPLORER;
        delete env.ETHERSCAN_API_KEY;
        env.PATH = cleanEnv.PATH;
        await run("deploy_04_mech_marketplace_proxy.sh");
        const fresh = await contract("MechMarketplace", config.mechMarketplaceProxyAddress);
        check("fresh proxy initialized with the intended owner", await fresh.owner() === owner.address);
        // Upgrade a proxy initialized with the repository's previous deployed-bytecode fixture.
        const oldArtifact = JSON.parse(fs.readFileSync(path.join(root, "abis/0.8.30/MechMarketplace.json"), "utf8"));
        let oldBytecode = typeof oldArtifact.bytecode === "string" ? oldArtifact.bytecode : oldArtifact.bytecode.object;
        if (!oldBytecode.startsWith("0x")) oldBytecode = "0x" + oldBytecode;
        const old = await new ethers.ContractFactory(oldArtifact.abi, oldBytecode, owner).deploy(registry.address, karma.address);
        await old.deployed();
        const proxy = await deploy("MechMarketplaceProxy", old.address,
            implementation.interface.encodeFunctionData("initialize", [100, 10, 20]));
        const marketplace = await contract("MechMarketplace", proxy.address);
        const legacyDomain = await marketplace.getDomainSeparator();
        config.mechMarketplaceProxyAddress = proxy.address;
        save();
        await (await karma.setMechMarketplaceStatuses([proxy.address], [true])).wait();
        for (const dependency of ["registry", "karma"]) {
            const wrongImplementation = await deploy("MechMarketplace",
                dependency === "registry" ? fresh.address : registry.address,
                dependency === "karma" ? fresh.address : karma.address);
            config.mechMarketplaceAddress = wrongImplementation.address;
            save();
            for (const planning of [false, true]) {
                await expectRejected("mismatched " + dependency + " stops " + (planning ? "calldata" : "direct") + " upgrade",
                    "script_06_change_implementaion_mech_marketplace_proxy.sh", planning ? ["--calldata"] : [],
                    "Implementation dependencies differ from the current proxy");
            }
        }
        config.mechMarketplaceAddress = implementation.address;
        save();
        const plannedUpgrade = await run("script_06_change_implementaion_mech_marketplace_proxy.sh", "--calldata");
        check("governance plan encodes the upgrade without executing it", plannedUpgrade.includes(
            implementation.interface.encodeFunctionData("changeImplementation", [implementation.address])) &&
            await proxy.getImplementation() === old.address);
        await run("script_06_change_implementaion_mech_marketplace_proxy.sh");
        check("upgrade retains the proxy and legacy signature domain", await proxy.getImplementation() === implementation.address &&
            await marketplace.getDomainSeparator() === legacyDomain);
        const domain = {name: "MechMarketplace", version: "2", chainId: 31337, verifyingContract: proxy.address};
        check("upgraded proxy exposes the standard explicit-nonce domain", await marketplace.getDomainSeparatorWithNonce() ===
            ethers.utils._TypedDataEncoder.hashDomain(domain));
        await run("deploy_05_mech_factory_fixed_price_native.sh");
        await run("deploy_07a_mech_factory_fixed_price_token_olas.sh");
        await run("deploy_07b_mech_factory_fixed_price_token_usdc.sh");
        const nativeTracker = await deploy("BalanceTrackerFixedPriceNative", proxy.address, owner.address, nativeAsset.address);
        const olasTracker = await deploy("BalanceTrackerFixedPriceToken", proxy.address, owner.address, olas.address);
        const usdcTracker = await deploy("BalanceTrackerFixedPriceToken", proxy.address, owner.address, usdc.address);
        Object.assign(config, {balanceTrackerFixedPriceNativeAddress: nativeTracker.address,
            balanceTrackerFixedPriceTokenOLASAddress: olasTracker.address, balanceTrackerFixedPriceTokenUSDCAddress: usdcTracker.address});
        save();
        config.usdcAddress = olas.address;
        save();
        for (const planning of [false, true]) {
            await expectRejected("wrong USDC asset stops " + (planning ? "calldata" : "direct") + " registration",
                "script_03a_marketplace_set_balance_trackers_fixed.sh", planning ? ["--calldata", "usdc"] : ["usdc"],
                "Tracker asset differs from configuration");
        }
        config.usdcAddress = usdc.address;
        save();
        // Code identity must be checked before sending or producing governance calldata.
        // Configure the intended trackers first so each rejection reaches its intended check.
        const factoryKeys = ["mechFactoryFixedPriceNativeAddress", "mechFactoryFixedPriceTokenOLASAddress", "mechFactoryFixedPriceTokenUSDCAddress"];
        const factoryArtifacts = ["MechFactoryFixedPriceNative", "MechFactoryFixedPriceToken", "MechFactoryFixedPriceTokenUSDC"];
        const factoryPaths = ["abis/0.8.28/MechFactoryFixedPriceNative.json", "abis/0.8.28/MechFactoryFixedPriceToken.json", "abis/0.8.30/MechFactoryFixedPriceTokenUSDC.json"];
        const payments = ["native", "olas", "usdc"];
        const trackerTypes = ["FixedPriceNative", "FixedPriceToken", "FixedPriceTokenUSDC"].map(ethers.utils.id);
        const trackerAddresses = [nativeTracker.address, olasTracker.address, usdcTracker.address];
        await (await marketplace.setPaymentTypeBalanceTrackers(trackerTypes, trackerAddresses)).wait();
        const expectedFactories = factoryKeys.map(key => config[key]);
        for (let i = 0; i < payments.length; ++i) {
            const artifact = JSON.parse(fs.readFileSync(path.join(root, factoryPaths[i]), "utf8"));
            let bytecode = typeof artifact.bytecode === "string" ? artifact.bytecode : artifact.bytecode.object;
            if (!bytecode.startsWith("0x")) bytecode = "0x" + bytecode;
            const oldFactory = await new ethers.ContractFactory(artifact.abi, bytecode, owner).deploy(proxy.address);
            await oldFactory.deployed();
            const otherProxyFactory = await deploy(factoryArtifacts[i], fresh.address);
            for (const scenario of [
                {name: "old factory", address: oldFactory.address, error: "Factory code does not match the current build"},
                {name: "wrong factory type", address: expectedFactories[(i + 1) % payments.length], error: "Factory code does not match the current build"},
                {name: "wrong proxy", address: otherProxyFactory.address, error: "Selected contract points to a different Marketplace"}
            ]) {
                config[factoryKeys[i]] = scenario.address;
                save();
                for (const planning of [false, true]) {
                    const beforeConfig = fs.readFileSync(globals, "utf8");
                    const beforeNonce = await owner.getTransactionCount("latest");
                    let failure;
                    try {
                        const extra = planning ? ["--calldata", payments[i]] : [payments[i]];
                        await run("script_02a_marketplace_set_factories_fixed.sh", ...extra);
                    } catch (error) {
                        failure = error;
                    }
                    check(payments[i] + " rejects " + scenario.name + " in " + (planning ? "calldata" : "direct") + " mode",
                        failure && failure.stderr.includes(scenario.error) && !failure.stdout.includes("Data:") &&
                        await owner.getTransactionCount("latest") === beforeNonce &&
                        fs.readFileSync(globals, "utf8") === beforeConfig);
                }
                config[factoryKeys[i]] = expectedFactories[i];
                save();
            }
        }
        // Check valid calldata too, using an independent standard ABI encoder.
        for (const selection of [[0], [1], [2], [2, 0], [0, 1, 2]]) {
            const chosenPayments = selection.map(index => payments[index]);
            const output = await run("script_02a_marketplace_set_factories_fixed.sh", "--calldata", ...chosenPayments);
            const encoded = marketplace.interface.encodeFunctionData("setMechFactoryStatuses", [
                selection.map(index => expectedFactories[index]), selection.map(() => true)
            ]);
            check("current factories produce correct calldata for " + chosenPayments.join("/"), output.includes("Data: " + encoded));
            const trackerOutput = await run("script_03a_marketplace_set_balance_trackers_fixed.sh", "--calldata", ...chosenPayments);
            const trackerEncoded = marketplace.interface.encodeFunctionData("setPaymentTypeBalanceTrackers", [
                selection.map(index => trackerTypes[index]), selection.map(index => trackerAddresses[index])
            ]);
            check("trackers produce correct calldata for " + chosenPayments.join("/"), trackerOutput.includes("Data: " + trackerEncoded));
        }

        // A previously configured, unselected tracker must survive a partial rollout.
        const previousUsdcTracker = await deploy("BalanceTrackerFixedPriceToken", proxy.address, owner.address, usdc.address);
        const usdcType = ethers.utils.id("FixedPriceTokenUSDC");
        const olasType = ethers.utils.id("FixedPriceToken");
        await (await marketplace.setPaymentTypeBalanceTrackers([usdcType], [previousUsdcTracker.address])).wait();
        const fullConfig = {...config};
        delete config.mechFactoryFixedPriceTokenUSDCAddress;
        delete config.balanceTrackerFixedPriceTokenUSDCAddress;
        delete config.usdcAddress;
        save();
        await run("script_03a_marketplace_set_balance_trackers_fixed.sh", "native", "olas");
        await run("script_02a_marketplace_set_factories_fixed.sh", "native", "olas");
        check("native/OLAS subset leaves the existing USDC tracker unchanged", await marketplace.mapPaymentTypeBalanceTrackers(usdcType) === previousUsdcTracker.address);
        check("native/OLAS subset leaves the USDC factory disabled", !await marketplace.mapMechFactories(fullConfig.mechFactoryFixedPriceTokenUSDCAddress));

        // Also check the other configuration subset, including an unselected disabled factory.
        config = {...fullConfig};
        await (await marketplace.setMechFactoryStatuses([fullConfig.mechFactoryFixedPriceTokenOLASAddress], [false])).wait();
        delete config.mechFactoryFixedPriceTokenOLASAddress;
        delete config.balanceTrackerFixedPriceTokenOLASAddress;
        delete config.olasAddress;
        save();
        await run("script_03a_marketplace_set_balance_trackers_fixed.sh", "native", "usdc");
        await run("script_02a_marketplace_set_factories_fixed.sh", "native", "usdc");
        check("native/USDC subset leaves the OLAS tracker unchanged", await marketplace.mapPaymentTypeBalanceTrackers(olasType) === olasTracker.address);
        check("native/USDC subset leaves the OLAS factory disabled", !await marketplace.mapMechFactories(fullConfig.mechFactoryFixedPriceTokenOLASAddress));

        config = {...fullConfig};
        save();
        const selected = ["native", "olas", "usdc"];
        await run("script_03a_marketplace_set_balance_trackers_fixed.sh", ...selected);
        await run("script_02a_marketplace_set_factories_fixed.sh", ...selected);
        const kinds = [
            {name: "native", type: "FixedPriceNative", factory: config.mechFactoryFixedPriceNativeAddress,
                mech: "MechFixedPriceNative", tracker: nativeTracker, asset: nativeAsset},
            {name: "OLAS", type: "FixedPriceToken", factory: config.mechFactoryFixedPriceTokenOLASAddress,
                mech: "MechFixedPriceToken", tracker: olasTracker, asset: olas},
            {name: "USDC", type: "FixedPriceTokenUSDC", factory: config.mechFactoryFixedPriceTokenUSDCAddress,
                mech: "MechFixedPriceTokenUSDC", tracker: usdcTracker, asset: usdc}
        ];
        const types = {ExplicitNonceDelivery: [
            {name: "mech", type: "address"}, {name: "requester", type: "address"}, {name: "data", type: "bytes"},
            {name: "maxDeliveryRate", type: "uint256"}, {name: "paymentType", type: "bytes32"},
            {name: "nonce", type: "uint256"}, {name: "deadline", type: "uint256"}
        ]};
        const selector = "deliverMarketplaceWithSignatures(address,(bytes,bytes,bytes)[],uint256[],uint256[],uint256[],uint256[],bytes)";
        for (let i = 0; i < kinds.length; ++i) {
            const kind = kinds[i];
            const service = i + 1;
            const paymentType = ethers.utils.id(kind.type);
            check(kind.name + " registration readbacks", await marketplace.mapMechFactories(kind.factory) &&
                await marketplace.mapPaymentTypeBalanceTrackers(paymentType) === kind.tracker.address);
            await (await registry.setServiceOwner(service, owner.address)).wait();
            const receipt = await (await marketplace.create(service, kind.factory,
                ethers.utils.defaultAbiCoder.encode(["uint256"], [100]))).wait();
            const mech = await contract(kind.mech, receipt.events.find(event => event.event === "CreateMech").args.mech);
            check(kind.name + " factory creates mech version 1.1.0", await mech.VERSION() === "1.1.0");
            if (i === 0) await (await kind.tracker.depositFor(requester.address, {value: 1000})).wait();
            else {
                await (await kind.asset.mint(owner.address, 1000)).wait();
                await (await kind.asset.approve(kind.tracker.address, 1000)).wait();
                await (await kind.tracker.depositFor(requester.address, 1000)).wait();
            }
            const deadline = (await provider.getBlock("latest")).timestamp + 3600;
            const message = {mech: mech.address, requester: requester.address, data: "0x1234",
                maxDeliveryRate: 100, paymentType, nonce: 77, deadline};
            const signature = await requester._signTypedData(domain, types, message);
            const digest = ethers.utils._TypedDataEncoder.hash(domain, types, message);
            await (await mech[selector](requester.address,
                [{requestData: message.data, deliveryData: "0xabcd", signature}], [80], [100], [77], [deadline], "0x")).wait();
            check(kind.name + " signed delivery settles after rollout", await marketplace.getRequestStatus(digest) === 3 &&
                (await mech.numTotalDeliveries()).eq(1) && (await kind.tracker.mapRequesterBalances(requester.address)).eq(920));
        }
        // Exercise generated operations through an actual 2-of-2 Safe owner.
        const safeArtifact = requireProject("@gnosis.pm/safe-contracts/build/artifacts/contracts/GnosisSafe.sol/GnosisSafe.json");
        const safeProxyArtifact = requireProject("@gnosis.pm/safe-contracts/build/artifacts/contracts/proxies/GnosisSafeProxy.sol/GnosisSafeProxy.json");
        const singleton = await new ethers.ContractFactory(safeArtifact.abi, safeArtifact.bytecode, owner).deploy();
        await singleton.deployed();
        const safeProxy = await new ethers.ContractFactory(safeProxyArtifact.abi, safeProxyArtifact.bytecode, owner).deploy(singleton.address);
        await safeProxy.deployed();
        const safe = new ethers.Contract(safeProxy.address, safeArtifact.abi, owner);
        const zero = ethers.constants.AddressZero;
        await (await safe.setup([owner.address, requester.address], 2, zero, "0x", zero, zero, 0, zero)).wait();
        // Deliberately change the starting state so successful execution must change readbacks.
        await (await marketplace.setPaymentTypeBalanceTrackers([usdcType], [previousUsdcTracker.address])).wait();
        await (await marketplace.setMechFactoryStatuses(expectedFactories, [false, false, false])).wait();
        await (await marketplace.changeOwner(safe.address)).wait();
        await expectRejected("an EOA cannot submit owner operations after ownership moves to the Safe",
            "script_03a_marketplace_set_balance_trackers_fixed.sh", selected,
            "Wallet is not Marketplace owner");
        const executePlan = async (name, script, args, expectedData) => {
            const beforeNonce = await owner.getTransactionCount("latest");
            const beforeConfig = fs.readFileSync(globals, "utf8");
            const output = await run(script, "--calldata", ...args);
            const target = output.match(/^Target: (0x[0-9a-fA-F]{40})$/m);
            const data = output.match(/^Data: (0x[0-9a-fA-F]+)$/m);
            check(name + " plan matches the independent encoder and submits nothing",
                target && target[1] === proxy.address && data && data[1] === expectedData &&
                output.includes("Chain: 31337") && output.includes("Value: 0") &&
                await owner.getTransactionCount("latest") === beforeNonce &&
                fs.readFileSync(globals, "utf8") === beforeConfig);
            const transaction = [target[1], 0, data[1], 0, 0, 0, 0, zero, zero];
            const hash = await safe.getTransactionHash(...transaction, await safe.nonce());
            const signatures = [owner, requester].sort((a, b) => a.address.toLowerCase().localeCompare(b.address.toLowerCase()))
                .map(wallet => ethers.utils.joinSignature(wallet._signingKey().signDigest(hash))).join("").replace(/0x/g, "");
            const receipt = await (await safe.execTransaction(...transaction, "0x" + signatures)).wait();
            check(name + " executes successfully through the 2-of-2 Safe",
                receipt.events.some(event => event.event === "ExecutionSuccess"));
        };
        const governanceImplementation = await deploy("MechMarketplace", registry.address, karma.address);
        config.mechMarketplaceAddress = governanceImplementation.address;
        save();
        await executePlan("governance upgrade", "script_06_change_implementaion_mech_marketplace_proxy.sh", [],
            marketplace.interface.encodeFunctionData("changeImplementation", [governanceImplementation.address]));
        check("governance upgrade changes the implementation and retains owner/domain",
            await proxy.getImplementation() === governanceImplementation.address &&
            await marketplace.owner() === safe.address && await marketplace.getDomainSeparator() === legacyDomain);
        await executePlan("governance tracker registration", "script_03a_marketplace_set_balance_trackers_fixed.sh", selected,
            marketplace.interface.encodeFunctionData("setPaymentTypeBalanceTrackers", [trackerTypes, trackerAddresses]));
        check("governance tracker registration changes the USDC mapping", await marketplace.mapPaymentTypeBalanceTrackers(usdcType) === usdcTracker.address);
        await executePlan("governance factory registration", "script_02a_marketplace_set_factories_fixed.sh", selected,
            marketplace.interface.encodeFunctionData("setMechFactoryStatuses", [expectedFactories, [true, true, true]]));
        check("governance factory registration enables all selected factories",
            (await Promise.all(expectedFactories.map(address => marketplace.mapMechFactories(address)))).every(Boolean));
        console.log("Local rollout checks passed:", checks.length);
    } finally {
        if (anvil.pid && anvil.exitCode === null) {
            await new Promise(resolve => {
                anvil.once("exit", resolve);
                anvil.kill("SIGTERM");
            });
        }
        fs.rmSync(temporary, {recursive: true, force: true});
    }
}

main().catch(error => {
    // Child-process errors can contain private-key arguments in `cmd`; never print the object.
    console.error("Local rollout failed:", error.code === "ERR_ASSERTION" ? error.message : error.stderr || error.reason || error.shortMessage || error.code || "assertion failed");
    process.exitCode = 1;
});
