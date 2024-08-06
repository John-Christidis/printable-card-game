//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PCGFactory} from "../../../src/PCGFactory.sol";
import {PriceConverter} from "../../../src/libraries/PriceConverter.sol";
import {PCG} from "../../../src/PCG.sol";
import {PCGEngine} from "../../../src/PCGEngine.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {DeployPCGContracts} from "../../../script/DeployPCGContracts.s.sol";

contract PCGEnginePurchaseTest is Test {
    event PCGCardsPurchased(uint256 indexed _purchaseId, address indexed _consumer, uint256 indexed _pcgId);

    using PriceConverter for uint256;

    PCGFactory pcgFactory;
    PCGEngine pcgEngine;
    HelperConfig helperConfig;
    PCG pcg;

    MockV3Aggregator nativeToUsdPriceFeed;
    MockV3Aggregator eurToUsdPriceFeed;

    string public URI = "http://test/id:{id}";
    uint256 public NUMBER_OF_MINTABLE_CARDS = 10;

    uint256 public STANDARD_TX_GUS_PRICE = 50_000_000_000;

    address public CONSUMER = makeAddr("consumer");
    uint256 public CONSUMER_BALANCE = 100 ether;

    function setUp() external {
        DeployPCGContracts deployer = new DeployPCGContracts();
        (pcgEngine, pcgFactory, helperConfig) = deployer.run();
        (,, address configNativeToUsdPriceFeedAddress, address configEurToUsdPriceFeedAddress,) =
            helperConfig.getNetworkConfig();

        nativeToUsdPriceFeed = MockV3Aggregator(configNativeToUsdPriceFeedAddress);
        eurToUsdPriceFeed = MockV3Aggregator(configEurToUsdPriceFeedAddress);

        vm.deal(CONSUMER, CONSUMER_BALANCE);
    }

    function test_PCGEngine_purchasePcgCards_revertsIfNumberOfCardsIsInvalid()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        uint256 pcgId = pcgFactory.getPcgCounter() - 1;
        uint32 zeroNumberOfCards = 0;
        (,,, uint256 zeroCardsPayment) = pcgEngine.estimatePcgCardsPrice(zeroNumberOfCards, uint96(tx.gasprice));
        uint32 moreThanPurchaseCardLimitNumberOfCards = pcgEngine.getMaxCardPurchaseLimit() + 1;
        (,,, uint256 moreThanLimitCardsPayment) =
            pcgEngine.estimatePcgCardsPrice(moreThanPurchaseCardLimitNumberOfCards, uint96(tx.gasprice));
        uint32 maxNumberOfCards = type(uint32).max;
        vm.startPrank(CONSUMER);
        vm.expectRevert(
            abi.encodeWithSelector(PCGEngine.PCGEngine__CardsToPurchaseCannotBeZeroOrLess.selector, zeroNumberOfCards)
        );
        pcgEngine.purchasePcgCards{value: zeroCardsPayment + 1}(pcgId, zeroNumberOfCards);
        vm.expectRevert(
            abi.encodeWithSelector(
                PCGEngine.PCGEngine__CardsToPurchaseMoreThanLimit.selector, moreThanPurchaseCardLimitNumberOfCards
            )
        );
        pcgEngine.purchasePcgCards{value: moreThanLimitCardsPayment + 1}(pcgId, moreThanPurchaseCardLimitNumberOfCards);
        vm.expectRevert(
            abi.encodeWithSelector(PCGEngine.PCGEngine__CardsToPurchaseMoreThanLimit.selector, maxNumberOfCards)
        );
        pcgEngine.purchasePcgCards{value: moreThanLimitCardsPayment + 1}(pcgId, maxNumberOfCards);
        vm.stopPrank();
    }

    function test_PCGEngine_purchasePcgCards_revertsWhenNativeIsLessThanVRFsCost()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        bool withGasReport = vm.envBool("WITH_GAS_REPORT");

        if (!withGasReport) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        }
        if (tx.gasprice != 0) {
            uint256 pcgId = pcgFactory.getPcgCounter() - 1;
            uint32 numberOfCards = 3;
            (, uint256 vrfCost,,) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
            vm.expectRevert(
                abi.encodeWithSelector(PCGEngine.PCGEngine__NotEnoughNativeToPayForVrf.selector, numberOfCards, vrfCost)
            );
            pcgEngine.purchasePcgCards{value: vrfCost - 1}(pcgId, numberOfCards);
        }
    }

    function test_PCGEngine_purchasePcgCards_revertsWhenNativeIsLessThanCardsPrice()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        bool withGasReport = vm.envBool("WITH_GAS_REPORT");

        if (!withGasReport) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        }
        uint256 pcgId = pcgFactory.getPcgCounter() - 1;
        uint32 numberOfCards = 3;
        (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
        vm.expectRevert(
            abi.encodeWithSelector(PCGEngine.PCGEngine__NotEnoughNativeToPurchaseCards.selector, numberOfCards)
        );
        pcgEngine.purchasePcgCards{value: totalPrice - 1}(pcgId, numberOfCards);
    }

    function test_PCGEngine_purchasePcgCards_revertsWhenPCGExpansionIsInvalid()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        uint256 pcgId = pcgFactory.getPcgCounter();
        uint32 numberOfCards = 3;
        (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
        vm.expectRevert(abi.encodeWithSelector(PCGEngine.PCGEngine__InvalidPCGExpansion.selector, pcgId));
        pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
        uint256 maxPcg = type(uint256).max;
        vm.expectRevert(abi.encodeWithSelector(PCGEngine.PCGEngine__InvalidPCGExpansion.selector, maxPcg));
        pcgEngine.purchasePcgCards{value: totalPrice + 1}(maxPcg, numberOfCards);
    }

    function test_PCGEngine_purchasePcgCards_updatesLastPriceConversion()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        uint256 pcgId = pcgFactory.getPcgCounter() - 1;
        uint32 numberOfCards = 3;
        uint256 lastPriceConversionBeforePurchase = pcgEngine.getLastPriceConverstion();
        if (block.chainid == 31337) {
            nativeToUsdPriceFeed.updateAnswer(2000_0000_0000);
        }
        (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
        vm.prank(CONSUMER);
        pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
        uint256 lastPriceConversionAfterPurchase = pcgEngine.getLastPriceConverstion();
        uint256 cardPriceInEur = 2 * 10 ** 18;
        (, uint256 currentPriceConversion) = cardPriceInEur.getConversionRate(
            address(nativeToUsdPriceFeed), address(eurToUsdPriceFeed), lastPriceConversionBeforePurchase
        );
        assertEq(currentPriceConversion, lastPriceConversionAfterPurchase);
    }

    function test_PCGEngine_purchasePcgCards_event_PCGCardsPurchased_isEmited()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        for (uint256 i = pcgEngine.getMinCardPurchaseLimit(); i <= pcgEngine.getMaxCardPurchaseLimit(); i++) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
            uint256 pcgId = pcgFactory.getPcgCounter() - 1;
            uint32 numberOfCards = uint32(i);
            //@dev The purchaseId of the event is created in the function thus cannot be tested in the emit
            //In the mock it can but these tests should also be used with forks.
            uint256 invalidId = 13;
            (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
            vm.recordLogs();
            vm.expectEmit(false, true, true, false);
            emit PCGCardsPurchased(invalidId, CONSUMER, pcgId);
            vm.prank(CONSUMER);
            pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            //@dev We take the third instead of the second entry since from the expectEmit we have another log on the first position
            bytes32 requestIdBytes = entries[2].topics[1];
            (address consumer, address pcgAddress, bool pending) = pcgEngine.getPurchase(uint256(requestIdBytes));
            assertEq(consumer, CONSUMER);
            assertEq(pcgAddress, pcgFactory.getPcg(0));
            assertEq(pending, true);
        }
    }

    function test_PCGEngine_purchasePcgCards_successfullyUpdatesThePurchasesMapping()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        for (uint256 i = pcgEngine.getMinCardPurchaseLimit(); i <= pcgEngine.getMaxCardPurchaseLimit(); i++) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
            uint256 pcgId = pcgFactory.getPcgCounter() - 1;
            uint32 numberOfCards = uint32(i);
            (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
            vm.prank(CONSUMER);
            vm.recordLogs();
            pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            bytes32 requestIdBytes = entries[1].topics[1];
            (address consumer, address pcgAddress, bool pending) = pcgEngine.getPurchase(uint256(requestIdBytes));
            assertEq(consumer, CONSUMER);
            assertEq(pcgAddress, pcgFactory.getPcg(0));
            assertEq(pending, true);
        }
    }

    modifier deployPcgExpansion(string memory _uri, uint256 _numberOfMintableCards) {
        vm.prank(pcgFactory.owner());
        pcgFactory.deployPCGExpansion(_uri, _numberOfMintableCards);
        pcg = PCG(pcgFactory.getPcg(pcgFactory.getPcgCounter() - 1));
        _;
    }

    function test_PCGEngine_purchasePcgCards_gasCost() external deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS) {
        vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        uint256 pcgId = pcgFactory.getPcgCounter() - 1;
        uint32 numberOfCards = 3;
        (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
        console.log("total cost: ", totalPrice);
        vm.prank(CONSUMER);
        pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
    }
}
