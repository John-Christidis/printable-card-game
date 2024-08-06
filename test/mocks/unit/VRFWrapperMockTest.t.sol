//SPDX-License-Identifier: MIT

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFWrapperMock} from "../VRFWrapperMock.sol";

//VERSION
pragma solidity 0.8.20;

contract VRFWrapperMockTest is Test {
    event FakeRandomWordsRequested(uint256 indexed requestId);

    VRFWrapperMock vrfWrapper;

    uint32 public wrapperGasOverhead = 13400;
    uint32 public fulfillmentFlatFeeNativePPM = 0;
    uint32 public fulfillmentTxSizeBytes = 580;
    uint8 public coordinatorNativePremiumPercentage = 24;
    uint32 public coordinatorGasOverheadPerWord = 435;
    uint32 public coordinatorGasOverheadNative = 90000;
    uint256 public CHAIN_SPECIFIC_UTIL_L1_CALLDATA_GAS_COST = 0;

    uint256 public STANDARD_TX_GUS_PRICE = 50_000_000_000;
    uint32 public CALLBACK_GAS_LIMIT = 200_000;
    uint16 public REQUEST_CONFIRMATIONS = 3;

    uint256 public BALANCE = 10 ether;

    function setUp() external {
        vrfWrapper = new VRFWrapperMock();
        vm.deal(address(this), BALANCE);
    }

    function test_VRFWrapper_constructor_variableSetCorrectly() external view {
        assertEq(vrfWrapper.s_wrapperGasOverhead(), wrapperGasOverhead);
        assertEq(vrfWrapper.s_fulfillmentTxSizeBytes(), fulfillmentTxSizeBytes);
        assertEq(vrfWrapper.s_coordinatorNativePremiumPercentage(), coordinatorNativePremiumPercentage);
        assertEq(vrfWrapper.s_coordinatorGasOverheadPerWord(), coordinatorGasOverheadPerWord);
        assertEq(vrfWrapper.s_coordinatorGasOverheadNative(), coordinatorGasOverheadNative);
        assertEq(vrfWrapper.s_fulfillmentTxSizeBytes(), fulfillmentTxSizeBytes);
        assertEq(vrfWrapper.CHAIN_SPECIFIC_UTIL_L1_CALLDATA_GAS_COST(), CHAIN_SPECIFIC_UTIL_L1_CALLDATA_GAS_COST);
        assert(vrfWrapper.link() != address(0));
        assertEq(vrfWrapper.s_nextRequestId(), 0);
    }

    function test_VRFWrapper_calculateRequestPriceNative_worksAsIntended() external {
        vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        uint256 vrfCost = vrfWrapper.calculateRequestPriceNative(CALLBACK_GAS_LIMIT, 1);
        uint256 expectedVrfCost = _getExpectedVrfCost(STANDARD_TX_GUS_PRICE, 1);
        assertEq(vrfCost, expectedVrfCost);
    }

    function test_VRFWrapper_estimateRequestPriceNative_worksAsIntended() external view {
        uint256 vrfCost = vrfWrapper.estimateRequestPriceNative(CALLBACK_GAS_LIMIT, 1, STANDARD_TX_GUS_PRICE);
        uint256 expectedVrfCost = _getExpectedVrfCost(STANDARD_TX_GUS_PRICE, 1);
        assertEq(vrfCost, expectedVrfCost);
    }

    function test_VRFWrapper_requestRandomWordsInNative_worksAsIntended() external {
        bool withGasReport = vm.envBool("WITH_GAS_REPORT");

        if (!withGasReport) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        }
        vm.startPrank(address(this));
        if (tx.gasprice != 0) {
            vm.expectRevert(bytes("Not enough ether"));
            vrfWrapper.requestRandomWordsInNative(CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, 3, "");
        }
        vm.expectRevert();
        vrfWrapper.requestRandomWordsInNative{value: 3 ether}(CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, 0, "");
        vm.expectEmit(true, false, false, false);
        emit FakeRandomWordsRequested(0);
        vrfWrapper.requestRandomWordsInNative{value: 3 ether}(CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, 3, "");
        uint256 previousNextRequestId = vrfWrapper.s_nextRequestId();
        vm.recordLogs();
        uint256 requestId =
            vrfWrapper.requestRandomWordsInNative{value: 3 ether}(CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, 3, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestIdBytes = entries[0].topics[1];
        assertEq(requestId, uint256(requestIdBytes));
        (address consumer, uint32 randomWords, uint16 requestConfirmations, uint32 callbackGasLimit) =
            vrfWrapper.s_requests(requestId);
        uint256 newNextRequestId = vrfWrapper.s_nextRequestId();
        assertEq(previousNextRequestId + 1, newNextRequestId);
        assertEq(consumer, address(this));
        assertEq(randomWords, 3);
        assertEq(requestConfirmations, REQUEST_CONFIRMATIONS);
        assertEq(callbackGasLimit, CALLBACK_GAS_LIMIT);
    }

    function test_VRFWrapper_triggerFulfillRandomness_worksAsIntended() external {
        vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        vm.prank(address(this));
        uint256 requestId =
            vrfWrapper.requestRandomWordsInNative{value: 3 ether}(CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, 3, "");
        uint256[] memory zeroWordsArray = new uint256[](0);
        vrfWrapper.triggerFulfillRandomness(requestId, zeroWordsArray);
        assertEq(wordsPerRequest[requestId].length, 3);

        uint256[] memory wrongNumberWordsArray = new uint256[](1);
        wrongNumberWordsArray[0] = 53;
        vm.expectRevert();
        vrfWrapper.triggerFulfillRandomness(requestId, wrongNumberWordsArray);

        uint256[] memory correctWordsArray = new uint256[](3);
        correctWordsArray[0] = 1;
        correctWordsArray[1] = 2;
        correctWordsArray[2] = 3;
        vrfWrapper.triggerFulfillRandomness(requestId, correctWordsArray);
        assertEq(wordsPerRequest[requestId].length, 3);
        for (uint256 i = 0; i < wordsPerRequest[requestId].length; i++) {
            assertEq(wordsPerRequest[requestId][i], correctWordsArray[i]);
        }
    }

    mapping(uint256 _requestId => uint256[] _words) public wordsPerRequest;

    function rawFulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) external {
        delete wordsPerRequest[_requestId];
        for (uint256 i = 0; i < _randomWords.length; i++) {
            wordsPerRequest[_requestId].push(_randomWords[i]);
        }
    }

    function _getExpectedVrfCost(uint256 _requestGasPriceWei, uint32 _numberOfCards) internal view returns (uint256) {
        uint256 wrapperCostWei = _requestGasPriceWei * wrapperGasOverhead;
        uint256 coordinatorGasOverhead = coordinatorGasOverheadNative + _numberOfCards * coordinatorGasOverheadPerWord;
        uint256 coordinatorCostWei = _requestGasPriceWei * (CALLBACK_GAS_LIMIT + coordinatorGasOverhead)
            + CHAIN_SPECIFIC_UTIL_L1_CALLDATA_GAS_COST;
        uint256 coordinatorCostWithPremiumAndFlatFeeWei = (
            (coordinatorCostWei * (coordinatorNativePremiumPercentage + 100)) / 100
        ) + (1e12 * uint256(fulfillmentFlatFeeNativePPM));
        uint256 expectedVrfCost = wrapperCostWei + coordinatorCostWithPremiumAndFlatFeeWei;
        return expectedVrfCost;
    }
}
