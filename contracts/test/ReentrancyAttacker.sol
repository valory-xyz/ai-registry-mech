// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;
import "../../lib/autonolas-registries/lib/solmate/src/tokens/ERC721.sol";

// AgentRegistry interface
interface IAgentRegistry {
    /// @dev Creates a unit.
    /// @param unitOwner Owner of the unit.
    /// @param unitHash IPFS CID hash of the unit.
    /// @return unitId The id of a minted unit.
    function create(address unitOwner, bytes32 unitHash) external returns (uint256 unitId);
}

contract ReentrancyAttacker is ERC721TokenReceiver {
    // Agent Registry
    address public immutable agentRegistry;

    // Signal of a bad action
    bool public badAction;

    constructor(address _agentRegistry) {
        agentRegistry = _agentRegistry;
    }

    /// @dev Lets attacker call create a component with onERC721Receive during the token mint.
    function createBadAgent(
        address _unitOwner,
        bytes32 _unitHash
    ) external returns (uint256 unitId)
    {
        unitId = IAgentRegistry(agentRegistry).create(_unitOwner, _unitHash);
    }

    /// @dev Malicious contract function call during the token mint.
    function onERC721Received(address, address, uint256, bytes memory) public override returns (bytes4) {
        IAgentRegistry(agentRegistry).create(address(this), bytes32(0));
        badAction = true;
        return this.onERC721Received.selector;
    }
}