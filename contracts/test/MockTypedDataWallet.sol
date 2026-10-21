// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Test-only ERC-1271 wallet covering opaque signatures and invalid validator responses.
contract MockTypedDataWallet {
    bytes32 public expectedHash;
    bytes32 public expectedSignatureHash;
    uint8 public mode;

    function configure(bytes32 hash, bytes calldata signature, uint8 validationMode) external {
        expectedHash = hash;
        expectedSignatureHash = keccak256(signature);
        mode = validationMode;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (mode == 2) revert("wallet rejected signature");
        if (mode == 3) {
            assembly {
                return(0, 0)
            }
        }
        if (mode == 0 && hash == expectedHash && keccak256(signature) == expectedSignatureHash) {
            return 0x1626ba7e;
        }
        return 0xffffffff;
    }
}
