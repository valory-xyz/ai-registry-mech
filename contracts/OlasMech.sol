// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrorsMech} from "./interfaces/IErrorsMech.sol";
import {ImmutableStorage} from "../lib/gnosis-mech/contracts/base/ImmutableStorage.sol";
import {IServiceRegistry} from "./interfaces/IServiceRegistry.sol";
import {Mech} from "../lib/gnosis-mech/contracts/base/Mech.sol";

/// @dev Mech Marketplace interface
interface IMechMarketplace {
    /// @dev Delivers requests.
    /// @notice This function can only be called by the mech delivering the request.
    /// @param requestIds Set of request ids.
    /// @param mechDeliveryRates Corresponding set of actual charged delivery rates for each request.
    /// @param deliveryDatas Set of corresponding self-descriptive opaque delivery data-blobs.
    function deliverMarketplace(uint256[] memory requestIds, uint256[] memory mechDeliveryRates,
        bytes[] memory deliveryDatas) external returns (bool[] memory deliveredRequests);
}

/// @dev A Mech that is operated by the multisig of an Olas service
abstract contract OlasMech is Mech, IErrorsMech, ImmutableStorage {
    event MaxDeliveryRateUpdated(uint256 maxDeliveryRate);
    event Deliver(address indexed sender, uint256 requestId, bytes data);
    event Request(uint256 requestId, bytes data);
    event RevokeRequest(uint256 requestId);
    event NumRequestsIncrease(uint256 numRequests);

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
    bool internal transient _locked;

    // TODO Check if needed as requests are checked by Marketplace
    // Cyclical map of request Ids
    mapping(uint256 => uint256[2]) public mapRequestIds;

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
    /// @param requestId Request Id.
    /// @param data Self-descriptive opaque data-blob.
    /// @return requestData Data for the request processing.
    function _preDeliver(uint256 requestId, bytes memory data) internal virtual returns (bytes memory requestData);

    /// @dev Registers a request.
    /// @param requestIds Set of request Ids.
    /// @param datas Set of corresponding self-descriptive opaque data-blobs.
    function _request(
        uint256[] memory requestIds,
        bytes[] memory datas
    ) internal virtual {
        uint256 numRequests = requestIds.length;

        for (uint256 i = 0; i < requestIds.length; ++i) {
            uint256 requestId = requestIds[i];

            // TODO optimize or remove?
            // Record the request Id in the map
            // Get previous and next request Ids of the first element
            uint256[2] storage requestIdLinks = mapRequestIds[0];
            // Create the new element
            uint256[2] storage newRequestIdLinks = mapRequestIds[requestId];

            // Previous element will be zero, next element will be the current next element
            uint256 curNextRequestIdLink = requestIdLinks[1];
            newRequestIdLinks[1] = curNextRequestIdLink;
            // Next element of the zero element will be the newly created element
            requestIdLinks[1] = requestId;
            // Previous element of the current next element will be the newly created element
            mapRequestIds[curNextRequestIdLink][0] = requestId;

            emit Request(requestId, datas[i]);
        }

        // Increase the number of undelivered requests
        numUndeliveredRequests += numRequests;
        // Increase the total number of requests
        numTotalRequests += numRequests;
    }

    /// @dev Prepares delivery of requests.
    /// @notice This function ultimately calls mech marketplace contract to finalize the delivery.
    /// @param requestIds Set of request Ids.
    /// @param datas Corresponding set of self-descriptive opaque delivery data-blobs.
    /// @return deliveryDatas Corresponding set of processed delivery datas.
    function _prepareDeliveries(
        uint256[] memory requestIds,
        bytes[] memory datas
    ) internal virtual returns (bytes[] memory deliveryDatas) {
        uint256 numRequests = requestIds.length;
        deliveryDatas = new bytes[](numRequests);

        uint256 numSelfRequests;
        // Traverse requests
        for (uint256 i = 0; i < numRequests; ++i) {
            uint256 requestId = requestIds[i];
            // Perform a pre-delivery of the data if it needs additional parsing
            deliveryDatas[i] = _preDeliver(requestId, datas[i]);

            // Clean request info
            // Get request Id from the request Ids map
            uint256[2] memory requestIdLinks = mapRequestIds[requestId];

            // Check if the request Id is invalid (non existent for this mech or delivered): previous and next request Ids
            // are zero, and the zero's element previous request Id is not equal to the provided request Id
            if (requestIdLinks[0] == 0 && requestIdLinks[1] == 0 && mapRequestIds[0][0] != requestId) {
                continue;
            } else {
                numSelfRequests++;
            }

            // Re-link previous and next elements between themselves
            mapRequestIds[requestIdLinks[0]][1] = requestIdLinks[1];
            mapRequestIds[requestIdLinks[1]][0] = requestIdLinks[0];

            // Delete the delivered element from the map
            delete mapRequestIds[requestId];
        }

        // Decrease the number of undelivered requests
        numUndeliveredRequests -= numSelfRequests;
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

    /// @dev Registers marketplace requests.
    /// @notice This function is called by the marketplace contract since this mech was specified as a priority one.
    /// @param requestIds Set of request Ids.
    /// @param datas Set of corresponding self-descriptive opaque data-blobs.
    function requestFromMarketplace(uint256[] memory requestIds, bytes[] memory datas) external {
        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceOnly(msg.sender, mechMarketplace);
        }

        // Perform requests
        _request(requestIds, datas);
    }

    /// @dev Updates number of requests delivered directly via Marketplace.
    /// @param numRequests Number of requests.
    function updateNumRequests(uint256 numRequests) external {
        // Check for marketplace access
        if (msg.sender != mechMarketplace) {
            revert MarketplaceOnly(msg.sender, mechMarketplace);
        }

        numTotalRequests += numRequests;
        numTotalDeliveries += numRequests;

        emit NumRequestsIncrease(numRequests);
    }

    /// @dev Delivers a request by a marketplace.
    /// @notice This function ultimately calls mech marketplace contract to finalize the delivery.
    /// @param requestIds Set of request ids.
    /// @param datas Corresponding set of self-descriptive opaque delivery data-blobs.
    function deliverToMarketplace(
        uint256[] memory requestIds,
        bytes[] memory datas
    ) external onlyOperator {
        // Reentrancy guard
        if (_locked) {
            revert ReentrancyGuard();
        }
        _locked = true;

        // Check array sizes
        if (requestIds.length == 0 || requestIds.length != datas.length) {
            revert WrongArrayLength(requestIds.length, datas.length);
        }

        // Preliminary delivery processing
        bytes[] memory deliveryDatas = _prepareDeliveries(requestIds, datas);

        // Get finalized delivery rates
        uint256[] memory deliveryRates = getFinalizedDeliveryRates(requestIds);

        // Mech marketplace delivery finalization
        // Some of deliveries might be front-run by other mechs, and thus only actually delivered ones are recorded
        bool[] memory deliveredRequests = IMechMarketplace(mechMarketplace).deliverMarketplace(requestIds,
            deliveryRates, deliveryDatas);

        uint256 numRequests = requestIds.length;
        uint256 numDeliveries;
        // Traverse all requests to select delivered ones
        for (uint256 i = 0; i < numRequests; ++i) {
            uint256 requestId = requestIds[i];
            if (deliveredRequests[i]) {
                numDeliveries++;
                emit Deliver(msg.sender, requestId, deliveryDatas[i]);
            } else {
                emit RevokeRequest(requestId);
            }
        }

        // Increase the total number of deliveries actually delivered by this mech
        numTotalDeliveries += numDeliveries;

        _locked = false;
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

    // TODO remove?
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

    /// @dev Gets finalized delivery rates for request Ids.
    /// @param requestIds Set of request Ids.
    /// @return deliveryRates Set of corresponding finalized delivery rates.
    function getFinalizedDeliveryRates(uint256[] memory requestIds) public view virtual returns (uint256[] memory deliveryRates);
}
