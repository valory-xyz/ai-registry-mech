# Internal audit of autonolas-staking-programmes
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/ai-registry-mech` <br>
commit: 7a8708d345a2201a1b693164f97dd9266532ea1b (tag: v0.4.0-pre-internal-audit2) <br> 

## Objectives
The audit focused on updated marketplace contracts in this repo. <br>
Limits: The subject of the audit is not contracts used as library contracts. Thus, this audit is not a full-fledged audit of contracts underlying the contract ERC721Mech. <br>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/ai-registry-mech/blob/main/audits/internal3/analysis/contracts)

### Security issues. Updated 20-12-24
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-staking-programmes/blob/main/audits/internal3/analysis/slither_full.txt) 
Most of the issues raised by instrumental analysis are outside the scope of the audit. <br>


### Issue
#### Medium. Make sure that the previous comments (internal - internal2) have been addressed.
[]

#### Medium. withdraw() vs processPayment()
```
function withdraw()
and
function processPayment()
They have the same logic, but in one it pays fee and in the other it doesn't. Double-check for logical bugs.
```
[]

#### Low. More Reentrancy protection
```
function checkAndRecordDeliveryRate()
function finalizeDeliveryRate() 
+ Reentrancy protection agains IMech(mech).maxDeliveryRate()
```
[]




