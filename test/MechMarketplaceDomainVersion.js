/*global describe, it*/

const { expect } = require("chai");
const { artifacts, ethers, run } = require("hardhat");
const {
    TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD,
    TASK_COMPILE_SOLIDITY_RUN_SOLC,
    TASK_COMPILE_SOLIDITY_RUN_SOLCJS
} = require("hardhat/builtin-tasks/task-names");

describe("MechMarketplace signature domain version", function () {
    it("keeps the legacy domain when the implementation VERSION is bumped", async function () {
        const sourceName = "contracts/MechMarketplace.sol";
        const build = await artifacts.getBuildInfo(sourceName + ":MechMarketplace");
        const input = JSON.parse(JSON.stringify(build.input));
        const source = input.sources[sourceName].content;
        const bumped = source.replace(/string public constant VERSION = "[^"]+";/,
            "string public constant VERSION = \"999.0.0\";");
        expect(bumped).not.to.equal(source);
        input.sources[sourceName].content = bumped;
        input.settings.outputSelection = { [sourceName]: { MechMarketplace: ["abi", "evm.bytecode.object"] } };
        const compiler = await run(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD,
            { quiet: true, solcVersion: build.solcVersion });
        const output = compiler.isSolcJs
            ? await run(TASK_COMPILE_SOLIDITY_RUN_SOLCJS, { input, solcJsPath: compiler.compilerPath })
            : await run(TASK_COMPILE_SOLIDITY_RUN_SOLC,
                { input, solcPath: compiler.compilerPath, solcVersion: build.solcVersion });
        expect((output.errors || []).filter((error) => error.severity === "error")).to.deep.equal([]);
        const compiled = output.contracts[sourceName].MechMarketplace;
        const [owner] = await ethers.getSigners();
        const factory = new ethers.ContractFactory(compiled.abi, compiled.evm.bytecode.object, owner);
        const candidate = await factory.deploy(owner.address, owner.address);
        await candidate.deployed();
        const Proxy = await ethers.getContractFactory("MechMarketplaceProxy");
        const proxy = await Proxy.deploy(candidate.address,
            candidate.interface.encodeFunctionData("initialize", [100, 10, 20]));
        await proxy.deployed();
        const marketplace = candidate.attach(proxy.address);
        expect(await marketplace.VERSION()).to.equal("999.0.0");
        const { chainId } = await ethers.provider.getNetwork();
        const expected = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
            ["bytes32", "bytes32", "bytes32", "uint256", "address"],
            [ethers.utils.id("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                ethers.utils.id("MechMarketplace"),
                ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["string"], ["1.1.0"])),
                chainId, proxy.address]));
        expect(await marketplace.getDomainSeparator()).to.equal(expected);
        expect(await marketplace.domainSeparator()).to.equal(expected);
    });
});
