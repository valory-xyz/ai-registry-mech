// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrorsMech} from "./interfaces/IErrorsMech.sol";
import {IMechMarketplace} from "./interfaces/IMechMarketplace.sol";
import {ImmutableStorage} from "../lib/gnosis-mech/contracts/base/ImmutableStorage.sol";
import {IServiceRegistry} from "./interfaces/IServiceRegistry.sol";
import {Mech} from "../lib/gnosis-mech/contracts/base/Mech.sol";

/// @dev A Mech that is operated by the multisig of an Olas service
abstract contract OlasMech is Mech, IErrorsMech, ImmutableStorage {
    event MaxDeliveryRateUpdated(uint256 maxDeliveryRate);
    event Deliver(address indexed sender, uint256 requestId, bytes data);
    event Request(address indexed sender, uint256 requestId, bytes data);
    event RevokeRequest(address indexed sender, uint256 requestId);

    // Olas mech version number
    string public constant VERSION = "1.0.0";
    // Mech marketplace address
    address public immutable mechMarketplace;
    // Mech payment type
    bytes32 public immutable paymentType;

    // TODO give it a better name
    // Maximum required delivery rate
    uint256 public maxDeliveryRate;
    // Number of undelivered requests by this mech
    uint256 public numUndeliveredRequests;
    // Number of total requests by this mech
    uint256 public numTotalRequests;
    // Number of total deliveries by this mech
    uint256 public numTotalDeliveries;
    // Reentrancy lock
    uint256 internal _locked = 1;

    // Map of undelivered requests counts for corresponding addresses in this agent mech
    mapping(address => uint256) public mapUndeliveredRequestsCounts;
    // Cyclical map of request Ids
    mapping(uint256 => uint256[2]) public mapRequestIds;
    // Map of request Id => sender address
    mapping(uint256 => address) public mapRequestAddresses;

    /// @dev OlasMech constructor.
    /// @param _mechMarketplace Mech marketplace address.
    /// @param _serviceRegistry Address of the registry contract.
    /// @param _serviceId Service Id.
    /// @param _maxDeliveryRate Mech max delivery rate.
    /// @param _paymentType Mech payment type.
    constructor(
        address _mechMarketplace,
        address _serviceRegistry,
        uint256 _serviceId,
        uint256 _maxDeliveryRate,
        bytes32 _paymentType
    ) {
        // Check for zero address
        if (_mechMarketplace == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero address
        if (_serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_serviceId == 0 || _maxDeliveryRate == 0 || _paymentType == 0) {
            revert ZeroValue();
        }

        bytes memory initParams = abi.encode(_serviceRegistry, _serviceId);
        (, address multisig, , , , , IServiceRegistry.ServiceState state) =
            IServiceRegistry(_serviceRegistry).mapServices(_serviceId);

        // Check for zero address
        if (multisig == address(0)) {
            revert ZeroAddress();
        }

        // Check for correct service state
        if (state != IServiceRegistry.ServiceState.Deployed) {
            revert WrongServiceState(uint256(state), _serviceId);
        }
        setUp(initParams);

        mechMarketplace = _mechMarketplace;
        maxDeliveryRate = _maxDeliveryRate;
        paymentType = _paymentType;
    }

    /// @dev Performs actions before the delivery of a request.
    /// @param requester Requester address.
    /// @param requestId Request Id.
    /// @param data Self-descriptive opaque data-blob.
    /// @return requestData Data for the request processing.
    function _preDeliver(
        address requester,
        uint256 requestId,
        bytes memory data
    ) internal virtual returns (bytes memory requestData);

    /// @dev Registers a request.
    /// @param requester Requester address.
    /// @param requestId Request Id.
    /// @param data Self-descriptive opaque data-blob.
    function _request(
        address requester,
        uint256 requestId,
        bytes memory data
    ) internal virtual {
        mapUndeliveredRequestsCounts[requester]++;
        // Record the requestId => sender correspondence
        mapRequestAddresses[requestId] = requester;

        // Record the request Id in the map
        // Get previous and next request Ids of the first element
        uint256[2] storage requestIds = mapRequestIds[0];
        // Create the new element
        uint256[2] storage newRequestIds = mapRequestIds[requestId];

        // Previous element will be zero, next element will be the current next element
        uint256 curNextRequestId = requestIds[1];
        newRequestIds[1] = curNextRequestId;
        // Next element of the zero element will be the newly created element
        requestIds[1] = requestId;
        // Previous element of the current next element will be the newly created element
        mapRequestIds[curNextRequestId][0] = requestId;

        // Increase the number of undelivered requests
        numUndeliveredRequests++;
        // Increase the total number of requests
        numTotalRequests++;

        emit Request(requester, requestId, data);
    }

    /// @dev Cleans the request info from all the relevant storage.
    /// @param requester Requester address.
    /// @param requestId Request Id.
    function _cleanRequestInfo(address requester, uint256 requestId) internal virtual {
        // Decrease the number of undelivered requests
        mapUndeliveredRequestsCounts[requester]--;
        numUndeliveredRequests--;

        // Remove delivered request Id from the request Ids map
        uint256[2] memory requestIds = mapRequestIds[requestId];
        // Check if the request Id is invalid (non existent or delivered): previous and next request Ids are zero,
        // and the zero's element previous request Id is not equal to the provided request Id
        if (requestIds[0] == 0 && requestIds[1] == 0 && mapRequestIds[0][0] != requestId) {
            revert RequestIdNotFound(requestId);
        }

        // Re-link previous and next elements between themselves
        mapRequestIds[requestIds[0]][1] = requestIds[1];
        mapRequestIds[requestIds[1]][0] = requestIds[0];

        // Delete the delivered element from the map
        delete mapRequestIds[requestId];
    }

    /// @dev Delivers a request.
    /// @notice This function ultimately calls mech marketplace contract to finalize the delivery.
    /// @param requestId Request id.
    /// @param data Self-descriptive opaque data-blob.
    function _deliver(uint256 requestId, bytes memory data) internal virtual returns (bytes memory requestData) {
        // Get an requester to deliver request to
        address requester = mapRequestAddresses[requestId];

        // Get the mech delivery info from the mech marketplace
        IMechMarketplace.MechDelivery memory mechDelivery =
            IMechMarketplace(mechMarketplace).mapRequestIdDeliveries(requestId);

        // Instantly return with empty data if the request has been delivered
        // This allows not to fail batch requests transactions
        if (mechDelivery.deliveryMech != address(0)) {
            return "";
        }

        // The requester is zero if the delivery mech is different from a priority mech, or if request does not exist
        if (requester == address(0)) {
            requester = mechDelivery.requester;
            // Check if request exists in the mech marketplace
            if (requester == address(0)) {
                revert RequestIdNotFound(requestId);
            }
            // Note, revoking the request for the priority mech happens later via revokeRequest
        } else {
            // The requester is non-zero if it is delivered by the priority mech
            _cleanRequestInfo(requester, requestId);
        }

        // Check for max delivery rate compared to requested one
        if (maxDeliveryRate > mechDelivery.deliveryRate) {
            revert Overflow(maxDeliveryRate, mechDelivery.deliveryRate);
        }

        // Perform a pre-delivery of the data if it needs additional parsing
        requestData = _preDeliver(requester, requestId, data);

        // Increase the total number of deliveries, as the request is delivered by this mech
        numTotalDeliveries++;

        emit Deliver(msg.sender, requestId, requestData);
    }

    /// @dev Sets the new max delivery rate.
    /// @param newMaxDeliveryRate New max delivery rate.
    function changeMaxDeliveryRate(uint256 newMaxDeliveryRate) external virtual onlyOperator {
        // Check for zero value
        if (newMaxDeliveryRate == 0) {
            revert ZeroValue();
        }

        maxDeliveryRate = newMaxDeliveryRate;
        emit MaxDeliveryRateUpdated(newMaxDeliveryRate);
    }

    /// @dev Registers a request by a marketplace.
    /// @notice This function is called by the marketplace contract since this mech was specified as a priority one.
    /// @param requester Requester address.
    /// @param data Self-descriptive opaque data-blob.
    /// @param requestId Request Id.
    function requestFromMarketplace(address requester, bytes memory data, uint256 requestId) external {
        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceNotAuthorized(msg.sender);
        }

        // Perform a request
        _request(requester, requestId, data);
    }

    /// @dev Revokes the request from the mech that does not deliver it.
    /// @notice Only marketplace can call this function if the request is not delivered by the chosen priority mech.
    /// @param requestId Request Id.
    function revokeRequest(uint256 requestId) external {
        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceNotAuthorized(msg.sender);
        }

        address requester = mapRequestAddresses[requestId];
        // This must never happen, as the priority mech recorded requestId => requester info during the request
        if (requester == address(0)) {
            revert ZeroAddress();
        }

        // Clean request info
        _cleanRequestInfo(requester, requestId);

        emit RevokeRequest(requester, requestId);
    }

    /// @dev Delivers a request by a marketplace.
    /// @notice This function ultimately calls mech marketplace contract to finalize the delivery.
    /// @param requestId Request id.
    /// @param data Self-descriptive opaque data-blob.
    function deliverToMarketplace(
        uint256 requestId,
        bytes memory data
    ) external onlyOperator {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Request delivery
        bytes memory requestData = _deliver(requestId, data);

        // Mech marketplace delivery finalization if the request was not delivered already
        if (requestData.length > 0) {
            IMechMarketplace(mechMarketplace).deliverMarketplace(requestId, requestData);
        }

        _locked = 1;
    }

    /// @dev Sets up a mech.
    /// @param initParams Mech initial parameters.
    function setUp(bytes memory initParams) public override {
        if (readImmutable().length != 0) {
            revert AlreadyInitialized();
        }
        writeImmutable(initParams);
    }

    /// @dev Gets mech token (service registry) address.
    /// @return serviceRegistry Service registry address.
    function token() external view returns (address serviceRegistry) {
        // Get service registry
        serviceRegistry = abi.decode(readImmutable(), (address));
    }

    /// @dev Gets mech token Id (service Id).
    /// @return serviceId Service Id.
    function tokenId() external view returns (uint256 serviceId) {
        // Get service Id
        (, serviceId) = abi.decode(readImmutable(), (address, uint256));
    }

    /// @dev Gets mech operator (service multisig).
    /// @return Service multisig address.
    function getOperator() public view returns (address) {
        // Get service registry and service Id
        (address serviceRegistry, uint256 serviceId) = abi.decode(readImmutable(), (address, uint256));

        (, address multisig, , , , , IServiceRegistry.ServiceState state) =
            IServiceRegistry(serviceRegistry).mapServices(serviceId);

        // Check for correct service state
        if (state != IServiceRegistry.ServiceState.Deployed) {
            revert WrongServiceState(uint256(state), serviceId);
        }

        return multisig;
    }

    /// @dev Checks the mech operator (service multisig).
    /// @param multisig Service multisig being checked against.
    /// @return True, if mech service multisig matches the provided one.
    function isOperator(address multisig) public view override returns (bool) {
        return multisig == getOperator();
    }

    /// @dev Gets the set of undelivered request Ids with Nonce.
    /// @param size Maximum batch size of a returned requests Id set. If the size is zero, the whole set is returned.
    /// @param offset The number of skipped requests that are not going to be part of the returned requests Id set.
    /// @return requestIds Set of undelivered request Ids.
    function getUndeliveredRequestIds(uint256 size, uint256 offset) external view returns (uint256[] memory requestIds) {
        // Get the number of undelivered requests
        uint256 numRequests = numUndeliveredRequests;

        // If size is zero, return all the requests
        if (size == 0) {
            size = numRequests;
        }

        // Check for the size + offset overflow
        if (size + offset > numRequests) {
            revert Overflow(size + offset, numRequests);
        }

        if (size > 0) {
            requestIds = new uint256[](size);

            // The first request Id is the next request Id of the zero element in the request Ids map
            uint256 curRequestId = mapRequestIds[0][1];
            // Traverse requests a specified offset
            for (uint256 i = 0; i < offset; ++i) {
                // Next request Id of the current element based on the current request Id
                curRequestId = mapRequestIds[curRequestId][1];
            }

            // Traverse the rest of requests
            for (uint256 i = 0; i < size; ++i) {
                requestIds[i] = curRequestId;
                // Next request Id of the current element based on the current request Id
                curRequestId = mapRequestIds[curRequestId][1];
            }
        }
    }

    /// @dev Gets finalized delivery rate for a request Id.
    /// @param requestId Request Id.
    /// @return Finalized delivery rate.
    function getFinalizedDeliveryRate(uint256 requestId) external virtual returns (uint256);
}
