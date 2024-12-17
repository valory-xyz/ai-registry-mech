# Internal audit of autonolas-staking-programmes
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/ai-registry-mech` <br>
commit: 7a8708d345a2201a1b693164f97dd9266532ea1b (tag: v0.4.0-pre-internal-audit) <br> 

## Objectives
The audit focused on updated marketplace contracts in this repo. <br>
Limits: The subject of the audit is not contracts used as library contracts. Thus, this audit is not a full-fledged audit of contracts underlying the contract ERC721Mech. <br>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/ai-registry-mech/blob/main/audits/internal1/analysis/contracts)

### Security issues. Updated 17-12-2024
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-staking-programmes/blob/main/audits/internal2/analysis/slither_full.txt) 
Most of the issues raised by instrumental analysis are outside the scope of the audit. <br>


### Issue
#### Medium _calculatePayment not update collectedFees;
```
function _calculatePayment(
        address mech,
        uint256 payment
    ) internal virtual returns (uint256 mechPayment, uint256 marketplaceFee) {
```
[]

#### Low? Notices? initialize and constructor on MechMarketplace + frontrunning 
```
This is not usually found in a same contract.
 /// @dev MechMarketplace constructor.
    /// @param _serviceRegistry Service registry contract address.
    /// @param _stakingFactory Staking factory contract address.
    /// @param _karma Karma proxy contract address.
    /// @param _wrappedNativeToken Wrapped native token address.
    /// @param _buyBackBurner Buy back burner address.
    constructor(
        address _serviceRegistry,
        address _stakingFactory,
        address _karma,
        address _wrappedNativeToken,
        address _buyBackBurner
    ) {
function initialize(uint256 _fee, uint256 _minResponseTimeout, uint256 _maxResponseTimeout) external {
Frontrunning is definitely possible: between constructor() -> initialize()
Move new address((new ) MechMarketplace ...) to Proxy?
```
[]

####  Low? Notices? OlasMech.setUp(bytes) event
[]

#### Low? Notices? Karma.sol Uniform approach to location getImplementation() (proxy/implementation)
```
Depending on what they understand better etherscan. Probably in proxy better.
    /// @dev Gets the implementation address.
    /// @return implementation Implementation address.
    function getImplementation() external view returns (address implementation) {
        // solhint-disable-next-line avoid-low-level-calls
        assembly {
            implementation := sload(KARMA_PROXY)
        }
    }
```
[]

#### Low? Notices? frontrunning initialize() in Karma.sol
```
deploy -> Karma -> frontrumming initialize() -> deploy KarmaProxy() -> initialize()! fail -> Karma

The implementation contract should be protected from direct initialization. 
To do this, a "dummy" can be installed in its constructor so that calls to the initialize() function (or similar function) are only possible through a proxy.
Example:
    constructor() {
        // dummy in context of implementation
        admin = address(1);
    }

    function initialize(address _admin) external {
        // in context of proxy
        require(admin == address(0), "Already initialized");
        admin = _admin;
    }
```
[]

#### Low? improvement create2(), due to unpredictability.
```
function createMech(
        address mechMarketplace,
        address serviceRegistry,
        uint256 serviceId,
        bytes memory payload
    ) external returns (address mech) {
        // Check payload length
        if (payload.length != 32) {
            revert IncorrectDataLength(payload.length, 32);
        }

        // Decode price
        uint256 price = abi.decode(payload, (uint256));

        // Get salt
        bytes32 salt = keccak256(abi.encode(block.timestamp, msg.sender, serviceId));

        // Service multisig is isOperator() for the mech
        mech = address((new MechFixedPrice){salt: salt}(mechMarketplace, serviceRegistry, serviceId, price));
+
require(mech != address(0), "Contract creation failed");
uint256 nonce = nonces[msg.sender]++;
bytes32 salt = keccak256(abi.encode(nonce, block.timestamp, msg.sender, serviceId));
```

### Notices. Variable "price". Problem of terminology
```
Problem of terminology. Price is usually expressed as amount0/amount1 
if (amount < price) {}
```

