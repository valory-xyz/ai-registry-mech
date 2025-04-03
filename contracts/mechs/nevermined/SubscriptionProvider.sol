// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface NVM {
    enum ConditionState { Uninitialized, Unfulfilled, Fulfilled, Aborted }

    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _returnAddress,
        address _lockPaymentAddress,
        address _tokenAddress,
        bytes32 _lockCondition,
        bytes32 _releaseCondition
    )
    external
    returns (ConditionState);

    /**
     * @notice fulfill the transfer NFT condition
     * @dev Fulfill method transfer a certain amount of NFTs
     *       to the _nftReceiver address in the DIDRegistry contract.
     *       When true then fulfill the condition
     * @param _agreementId agreement identifier
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _nftReceiver is the address of the account to receive the NFT
     * @param _nftAmount amount of NFTs to transfer
     * @param _lockPaymentCondition lock payment condition identifier
     * @param _nftHolder is the address of the account to receive the NFT
     * @param _nftContractAddress the address of the ERC-1155 NFT contract
     * @param _transfer if yes it does a transfer if false it mints the NFT
     * @param _expirationBlock Block in which the token expires. If zero means no expiration
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfillForDelegate(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftHolder,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition,
        address _nftContractAddress,
        bool _transfer,
        uint256 _expirationBlock
    )
    external
    returns (ConditionState);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @title SubscriptionProvider - smart contract for subscription provider management
contract SubscriptionProvider {
    event SubscriptionSet(address indexed token, uint256 indexed tokenId);
    event RequesterCreditsRedeemed(address indexed account, uint256 amount);

    // Subscription token Id
    uint256 public immutable subscriptionTokenId;
    // Subscription NFT
    address public immutable subscriptionNFT;
    // DID registry address
    address public immutable didRegistry;
    // Transfer NFT Condition address
    address public immutable transferNFTCondition;
    // Escrow Payment Condition address
    address public immutable escrowPaymentCondition;

    // Temporary owner address
    address public owner;

    /// @dev SubscriptionProvider constructor.
    constructor(
        uint256 _subscriptionTokenId,
        address _subscriptionNFT,
        address _didRegistry,
        address _transferNFTCondition,
        address _escrowPaymentCondition
    ) {
        subscriptionTokenId = _subscriptionTokenId;
        subscriptionNFT = _subscriptionNFT;
        didRegistry = _didRegistry;
        transferNFTCondition = _transferNFTCondition;
        escrowPaymentCondition = _escrowPaymentCondition;

        owner = msg.sender;
    }

    function fulfillForDelegate(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftHolder,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition,
        address _nftContractAddress,
        bool _transfer,
        uint256 _expirationBlock
    ) external returns (NVM.ConditionState) {
        return NVM(transferNFTCondition).fulfillForDelegate(_agreementId, _did, _nftHolder, _nftReceiver, _nftAmount,
            _lockPaymentCondition, _nftContractAddress, _transfer, _expirationBlock);
    }

    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _returnAddress,
        address _lockPaymentAddress,
        address _tokenAddress,
        bytes32 _lockCondition,
        bytes32 _releaseCondition
    ) external returns (NVM.ConditionState) {
        return NVM(escrowPaymentCondition).fulfill(_agreementId, _did, _amounts, _receivers, _returnAddress,
            _lockCondition, _tokenAddress, _lockCondition, _releaseCondition);
    }
}