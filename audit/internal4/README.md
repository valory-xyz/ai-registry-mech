# Internal audit of autonolas-staking-programmes
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/ai-registry-mech` <br>
commit: 4f5c44c069e5c94435420abbbac6e0f0cba67c39 (tag: v0.4.0-pre-internal-audit3) <br> 

## Objectives
The audit focused on updated marketplace contracts in this repo. <br>
Limits: The subject of the audit is not contracts used as library contracts. Thus, this audit is not a full-fledged audit of contracts underlying the contract ERC721Mech. <br>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/ai-registry-mech/blob/main/audits/internal4/analysis/contracts)

### Security issues. Updated 06-01-24
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-staking-programmes/blob/main/audits/internal4/analysis/slither_full.txt) 
Most of the issues raised by instrumental analysis are outside the scope of the audit. <br>


### Issue
#### Low issue: Not checking mech != address(0) in checkMech
```
function checkMech(address mech) public view returns (address multisig) {
        uint256 mechServiceId = IMech(mech).tokenId();

        // Check mech validity as it must be created and recorded via this marketplace
        // ISSUE address(0) != address(0)
        if (mapServiceIdMech[mechServiceId] != mech) {
            revert UnauthorizedAccount(mech);
        }

        // Check mech service Id and get its multisig
        multisig = IMech(mech).getOperator();
    }
Not checking mech != address(0)
```

