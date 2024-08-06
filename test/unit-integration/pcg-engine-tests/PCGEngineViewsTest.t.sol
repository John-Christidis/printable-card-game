//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PCGFactory} from "../../../src/PCGFactory.sol";
import {PCG} from "../../../src/PCG.sol";
import {PCGEngine} from "../../../src/PCGEngine.sol";
import {VRFWrapperMock} from "../../mocks/VRFWrapperMock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {DeployPCGContracts} from "../../../script/DeployPCGContracts.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {PriceConverter} from "../../../src/libraries/PriceConverter.sol";

contract PCGEngineViewsTest is Test {
    using PriceConverter for uint256;

    PCGFactory pcgFactory;
    PCGEngine pcgEngine;
    PCG pcg;

    VRFWrapperMock vrfWrapper;
    MockV3Aggregator nativeToUsdPriceFeed;
    MockV3Aggregator eurToUsdPriceFeed;
    uint32 callbackGasLimit;

    uint16 public REQUEST_CONFIRMATIONS = 3;
    uint256 public CARD_PRICE_EUR = 2 * 10 ** 18;
    uint256 lastPriceConversion;

    string public URI = "http://test/id:{id}";
    uint256 public EXPANSION = 0;
    uint256 public NUMBER_OF_MINTABLE_CARDS = 10;
    uint256 public RUNS = 10;
    uint256 public STANDARD_TX_GUS_PRICE = 50_000_000_000;

    uint32 public wrapperGasOverhead;
    uint32 public fulfillmentFlatFeeNativePPM;
    uint32 public fulfillmentTxSizeBytes;
    uint8 public coordinatorNativePremiumPercentage;
    uint32 public coordinatorGasOverheadPerWord;
    uint32 public coordinatorGasOverheadNative;
    uint256 public CHAIN_SPECIFIC_UTIL_L1_CALLDATA_GAS_COST = 0;

    address public CONSUMER = makeAddr("consumer");
    uint256 public CONSUMER_BALANCE = 100 ether;

    function setUp() external {
        DeployPCGContracts deployer = new DeployPCGContracts();
        HelperConfig helperConfig;
        (pcgEngine, pcgFactory, helperConfig) = deployer.run();
        (
            address vrfWrapperAddress,
            uint32 _callbackGasLimit,
            address nativeToUsdPriceFeedAddress,
            address eurToUsdPriceFeedAddress,
        ) = helperConfig.getNetworkConfig();
        callbackGasLimit = _callbackGasLimit;
        vrfWrapper = VRFWrapperMock(vrfWrapperAddress);
        nativeToUsdPriceFeed = MockV3Aggregator(nativeToUsdPriceFeedAddress);
        eurToUsdPriceFeed = MockV3Aggregator(eurToUsdPriceFeedAddress);

        if (block.chainid == 11155111) {
            //sepolia
            wrapperGasOverhead = 13400;
            fulfillmentFlatFeeNativePPM = 0;
            fulfillmentTxSizeBytes = 580;
            coordinatorNativePremiumPercentage = 24;
            coordinatorGasOverheadPerWord = 435;
            coordinatorGasOverheadNative = 90000;
        } else if (block.chainid == 80002) {
            //matic amoy
            wrapperGasOverhead = 13400;
            fulfillmentFlatFeeNativePPM = 0;
            fulfillmentTxSizeBytes = 580;
            coordinatorNativePremiumPercentage = 84;
            coordinatorGasOverheadPerWord = 435;
            coordinatorGasOverheadNative = 99500;
        } else {
            // anvil
            wrapperGasOverhead = 13400;
            fulfillmentFlatFeeNativePPM = 0;
            fulfillmentTxSizeBytes = 580;
            coordinatorNativePremiumPercentage = 24;
            coordinatorGasOverheadPerWord = 435;
            coordinatorGasOverheadNative = 90000;
        }

        vm.deal(CONSUMER, CONSUMER_BALANCE);
    }

    function test_PCGEngine_estimateCardsPrice_returnsExpectedResult() external view {
        for (uint32 i = pcgEngine.getMinCardPurchaseLimit(); i <= pcgEngine.getMaxCardPurchaseLimit(); i++) {
            (uint32 numberOfCards, uint256 vrfCosts, uint256 cardsPriceInNative, uint256 totalPrice) =
                pcgEngine.estimatePcgCardsPrice(i, uint96(STANDARD_TX_GUS_PRICE));

            uint256 expectedVrfCost = _getExpectedVrfCost(STANDARD_TX_GUS_PRICE, i);
            uint256 expectedCardsPrice = _getExpectedCardsPrice(i);

            assertEq(numberOfCards, i);
            assertEq(vrfCosts, expectedVrfCost);
            assertEq(cardsPriceInNative, expectedCardsPrice);
            assertEq(totalPrice, expectedVrfCost + expectedCardsPrice);
        }
    }

    function test_PCGEngine_estimateCardsPrice_returnsExpectedResultWhenUsingNumberOfCardsBelowPurchaseLimit()
        external
        view
    {
        uint32 zeroNumberOfCards = 0;
        (uint32 numberOfCards, uint256 vrfCosts, uint256 cardsPriceInNative, uint256 totalPrice) =
            pcgEngine.estimatePcgCardsPrice(zeroNumberOfCards, uint96(STANDARD_TX_GUS_PRICE));

        uint256 expectedVrfCost = _getExpectedVrfCost(STANDARD_TX_GUS_PRICE, pcgEngine.getMinCardPurchaseLimit());
        uint256 expectedCardsPrice = _getExpectedCardsPrice(pcgEngine.getMinCardPurchaseLimit());

        assertEq(numberOfCards, pcgEngine.getMinCardPurchaseLimit());
        assertEq(vrfCosts, expectedVrfCost);
        assertEq(cardsPriceInNative, expectedCardsPrice);
        assertEq(totalPrice, expectedVrfCost + expectedCardsPrice);
    }

    function test_PCGEngine_estimateCardsPrice_returnsExpectedResultWhenUsingNumberOfCardsAbovePurchaseLimit()
        external
        view
    {
        uint32 invalidNumberOfCards = 13;
        (uint32 numberOfCards, uint256 vrfCosts, uint256 cardsPriceInNative, uint256 totalPrice) =
            pcgEngine.estimatePcgCardsPrice(invalidNumberOfCards, uint96(STANDARD_TX_GUS_PRICE));

        uint256 expectedVrfCost = _getExpectedVrfCost(STANDARD_TX_GUS_PRICE, pcgEngine.getMaxCardPurchaseLimit());
        uint256 expectedCardsPrice = _getExpectedCardsPrice(pcgEngine.getMaxCardPurchaseLimit());

        assertEq(numberOfCards, pcgEngine.getMaxCardPurchaseLimit());
        assertEq(vrfCosts, expectedVrfCost);
        assertEq(cardsPriceInNative, expectedCardsPrice);
        assertEq(totalPrice, expectedVrfCost + expectedCardsPrice);
    }

    function test_PCGEngine_getPurchase_returnsExpectedResultsWhenEmpty() external view {
        for (uint256 i = 0; i < RUNS; i++) {
            (address consumer, address pcgAddress, bool pending) = pcgEngine.getPurchase(i);
            assertEq(consumer, address(0));
            assertEq(pcgAddress, address(0));
            assertEq(pending, false);
        }
    }

    function test_PCGEngine_getPurchase_returnsTrueWhenPurchaseIsPending()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        uint256 pcgId = pcgFactory.getPcgCounter() - 1;
        vm.prank(CONSUMER);
        vm.recordLogs();
        pcgEngine.purchasePcgCards{value: 50 ether}(pcgId, 3);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestIdBytes = entries[1].topics[1];
        (address consumer, address pcgAddress, bool pending) = pcgEngine.getPurchase(uint256(requestIdBytes));
        assertEq(consumer, CONSUMER);
        assertEq(pcgAddress, address(pcg));
        assertEq(pending, true);
    }

    function test_PCGEngine_getPurchase_returnsFalseWhenPurchaseIsNotPending()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        uint256 pcgId = pcgFactory.getPcgCounter() - 1;
        vm.prank(CONSUMER);
        vm.recordLogs();
        pcgEngine.purchasePcgCards{value: 30 ether}(pcgId, 3);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestIdBytes = entries[1].topics[1];
        uint256[] memory wordsArray = new uint256[](3);
        for (uint256 j = 0; j < wordsArray.length; j++) {
            // i=1 ids=(0)
            // i=2 ids=(0, 1)
            // i=3 ids=(0, 1, 2)
            wordsArray[j] = j;
        }
        if (block.chainid == 31337) {
            vrfWrapper.triggerFulfillRandomness(uint256(requestIdBytes), wordsArray);
        } else {
            vm.prank(address(vrfWrapper));
            pcgEngine.rawFulfillRandomWords(uint256(requestIdBytes), wordsArray);
        }

        (address consumer, address pcgAddress, bool pending) = pcgEngine.getPurchase(uint256(requestIdBytes));
        assertEq(consumer, CONSUMER);
        assertEq(pcgAddress, address(pcg));
        assertEq(pending, false);
    }

    function _getExpectedVrfCost(uint256 _requestGasPriceWei, uint32 _numberOfCards) internal view returns (uint256) {
        uint256 wrapperCostWei = _requestGasPriceWei * wrapperGasOverhead;
        uint256 coordinatorGasOverhead = coordinatorGasOverheadNative + _numberOfCards * coordinatorGasOverheadPerWord;
        uint256 coordinatorCostWei =
            _requestGasPriceWei * (callbackGasLimit + coordinatorGasOverhead) + CHAIN_SPECIFIC_UTIL_L1_CALLDATA_GAS_COST;
        uint256 coordinatorCostWithPremiumAndFlatFeeWei = (
            (coordinatorCostWei * (coordinatorNativePremiumPercentage + 100)) / 100
        ) + (1e12 * uint256(fulfillmentFlatFeeNativePPM));
        uint256 expectedVrfCost = wrapperCostWei + coordinatorCostWithPremiumAndFlatFeeWei;
        return expectedVrfCost;
    }

    function _getExpectedCardsPrice(uint32 _numberOfCards) internal view returns (uint256) {
        uint256 amount = _numberOfCards * pcgEngine.getCardPrice();
        uint256 eurAmountInNative = amount.getReverseConversionRate(
            address(nativeToUsdPriceFeed), address(eurToUsdPriceFeed), lastPriceConversion
        );
        return eurAmountInNative;
    }

    modifier deployPcgExpansion(string memory _uri, uint256 _numberOfMintableCards) {
        vm.prank(pcgFactory.owner());
        pcgFactory.deployPCGExpansion(_uri, _numberOfMintableCards);
        pcg = PCG(pcgFactory.getPcg(pcgFactory.getPcgCounter() - 1));
        _;
    }
}
