/*global process*/

// Read-only post-upgrade check; this command never uses a signing wallet.
const {ethers} = require("ethers");

class DomainCheckError extends Error {}

async function main() {
    const [proxy, chainId] = process.argv.slice(2);
    if (process.argv.length !== 4 || !ethers.utils.isAddress(proxy) || proxy === ethers.constants.AddressZero ||
        !/^[0-9]+$/.test(chainId || "")) {
        throw new DomainCheckError("Usage: node scripts/deployment/check_marketplace_domain.js <proxy address> <chain ID>");
    }
    if (!process.env.MARKETPLACE_RPC_URL) throw new DomainCheckError("Set MARKETPLACE_RPC_URL");
    const provider = new ethers.providers.StaticJsonRpcProvider(process.env.MARKETPLACE_RPC_URL);
    let actualChain, actualDomain;
    try {
        actualChain = await provider.send("eth_chainId", []);
    } catch {
        throw new DomainCheckError("Cannot read RPC chain ID");
    }
    if (!ethers.BigNumber.from(actualChain).eq(chainId)) throw new DomainCheckError("RPC chain ID does not match the target");
    const marketplace = new ethers.Contract(proxy, ["function getDomainSeparatorWithNonce() view returns (bytes32)"], provider);
    try {
        actualDomain = await marketplace.getDomainSeparatorWithNonce();
    } catch {
        throw new DomainCheckError("Cannot read the explicit-nonce domain from the target proxy");
    }
    const expectedDomain = ethers.utils._TypedDataEncoder.hashDomain({
        name: "MechMarketplace", version: "2", chainId, verifyingContract: proxy
    });
    if (actualDomain.toLowerCase() !== expectedDomain.toLowerCase()) throw new DomainCheckError("Explicit-nonce domain does not match the expected EIP-712 domain");
    console.log("Explicit-nonce domain confirmed:", expectedDomain);
}

main().catch(error => {
    // RPC diagnostics can include credentials; print only messages defined in this script.
    console.error("Error:", error instanceof DomainCheckError ? error.message : "Cannot validate the explicit-nonce domain");
    process.exitCode = 1;
});
