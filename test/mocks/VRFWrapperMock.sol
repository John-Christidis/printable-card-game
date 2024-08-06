//SPDX-License-Identifier: MIT

import {VRFV2PlusWrapperConsumerBase} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import {MockLinkToken} from "@chainlink/contracts/src/v0.8/mocks/MockLinkToken.sol";
//If you wan to add arbitrum or optimism you need to use this lib
//import {ChainSpecificUtil} from "@chainlink/contracts/src/v0.8/ChainSpecificUtil.sol";

//VERSION
pragma solidity 0.8.20;

contract VRFWrapperMock {
    event FakeRandomWordsRequested(uint256 indexed requestId);

    struct Request {
        address consumer;
        uint32 randomWords;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
    }

    mapping(uint256 _requestId => Request _request) public s_requests;
    uint256 public s_nextRequestId;
    //these tests do not work on arbitrum or optimism since they have different configuration

    uint32 public s_wrapperGasOverhead = 13400;
    uint32 public s_fulfillmentFlatFeeNativePPM = 0;
    uint32 public s_fulfillmentTxSizeBytes = 580;
    uint8 public s_coordinatorNativePremiumPercentage = 24;
    uint32 public s_coordinatorGasOverheadPerWord = 435;
    uint32 public s_coordinatorGasOverheadNative = 90000;
    uint256 public CHAIN_SPECIFIC_UTIL_L1_CALLDATA_GAS_COST = 0;

    MockLinkToken mockLinkToken;

    constructor() {
        s_nextRequestId = 0;
        mockLinkToken = new MockLinkToken();
    }

    function requestRandomWordsInNative(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _randomWords,
        bytes calldata extraArgs
    ) external payable returns (uint256) {
        require(
            msg.value >= _calculateRequestPriceNative(_callbackGasLimit, _randomWords, tx.gasprice), "Not enough ether"
        );
        require(_randomWords > 0);
        uint256 currentRequestId = s_nextRequestId;
        Request storage _request = s_requests[currentRequestId];
        _request.consumer = msg.sender;
        _request.randomWords = _randomWords;
        _request.callbackGasLimit = _callbackGasLimit;
        _request.requestConfirmations = _requestConfirmations;

        s_nextRequestId++;
        emit FakeRandomWordsRequested(currentRequestId);
        return currentRequestId;
    }

    function calculateRequestPriceNative(uint32 _callbackGasLimit, uint32 _randomWords)
        external
        view
        returns (uint256)
    {
        return _calculateRequestPriceNative(_callbackGasLimit, _randomWords, tx.gasprice);
    }

    function _calculateRequestPriceNative(uint32 _callbackGasLimit, uint32 _randomWords, uint256 _requestGasPriceWei)
        internal
        view
        returns (uint256)
    {
        // costWei is the base fee denominated in wei (native)
        // (wei/gas) * gas
        uint256 wrapperCostWei = _requestGasPriceWei * s_wrapperGasOverhead;

        // coordinatorCostWei takes into account the L1 posting costs of the VRF fulfillment transaction, if we are on an L2.
        // (wei/gas) * gas + l1wei
        uint256 coordinatorCostWei = _requestGasPriceWei
            * (_callbackGasLimit + _getCoordinatorGasOverhead(_randomWords)) + CHAIN_SPECIFIC_UTIL_L1_CALLDATA_GAS_COST;
        // when working on arbitrum or optimism use these: ChainSpecificUtil._getL1CalldataGasCost(s_fulfillmentTxSizeBytes);
        // instead of this FLAT_CHAIN_SPECIFIC_UTIL_L1_CALLDATA_GAS_COST

        // coordinatorCostWithPremiumAndFlatFeeWei is the coordinator cost with the percentage premium and flat fee applied
        // coordinator cost * premium multiplier + flat fee
        uint256 coordinatorCostWithPremiumAndFlatFeeWei = (
            (coordinatorCostWei * (s_coordinatorNativePremiumPercentage + 100)) / 100
        ) + (1e12 * uint256(s_fulfillmentFlatFeeNativePPM));

        return wrapperCostWei + coordinatorCostWithPremiumAndFlatFeeWei;
    }

    function estimateRequestPriceNative(uint32 _callbackGasLimit, uint32 _randomWords, uint256 _requestGasPriceWei)
        external
        view
        returns (uint256)
    {
        return _calculateRequestPriceNative(_callbackGasLimit, _randomWords, _requestGasPriceWei);
    }

    function _getCoordinatorGasOverhead(uint32 numWords) internal view returns (uint32) {
        return s_coordinatorGasOverheadNative + numWords * s_coordinatorGasOverheadPerWord;
    }

    function triggerFulfillRandomness(uint256 _requestId, uint256[] memory _randomWords) external {
        Request storage _request = s_requests[_requestId];
        if (_randomWords.length == 0) {
            _randomWords = new uint256[](_request.randomWords);
            for (uint256 i = 0; i < _request.randomWords; i++) {
                _randomWords[i] = uint256(keccak256(abi.encode(_requestId, i)));
            }
        } else if (_randomWords.length != _request.randomWords) {
            revert();
        }
        VRFV2PlusWrapperConsumerBase c = VRFV2PlusWrapperConsumerBase(_request.consumer);
        c.rawFulfillRandomWords(_requestId, _randomWords);
    }

    function link() external view returns (address) {
        return address(mockLinkToken);
    }
}
