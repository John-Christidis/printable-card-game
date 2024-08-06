//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PCGFactory} from "../../../src/PCGFactory.sol";
import {PCG} from "../../../src/PCG.sol";
import {PCGEngine} from "../../../src/PCGEngine.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {VRFWrapperMock} from "../../mocks/VRFWrapperMock.sol";
import {DeployPCGContracts} from "../../../script/DeployPCGContracts.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";

contract PCGEngineFulfillTest is Test {
    event PCGCardsPurchaseFullfilled(
        uint256 indexed _purchaseId, address indexed _consumer, address indexed _pcgAddress
    );
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(
        address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values
    );

    PCGFactory pcgFactory;
    PCGEngine pcgEngine;
    PCG pcg;
    VRFWrapperMock vrfWrapper;

    string public URI = "http://test/id:{id}";
    uint256 public NUMBER_OF_MINTABLE_CARDS = 10;
    uint256 public STANDARD_TX_GUS_PRICE = 50_000_000_000;

    address public CONSUMER = makeAddr("consumer");
    uint256 public CONSUMER_BALANCE = 100 ether;

    function setUp() external {
        DeployPCGContracts deployer = new DeployPCGContracts();
        HelperConfig helperConfig;
        (pcgEngine, pcgFactory, helperConfig) = deployer.run();
        (address configVrfWrapperAddress,,,,) = helperConfig.getNetworkConfig();
        vrfWrapper = VRFWrapperMock(configVrfWrapperAddress);

        vm.deal(CONSUMER, CONSUMER_BALANCE);
    }

    function test_PCGEngine_fulfillRandomWords_revertsWhenPurchaseIsNotPending()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        for (uint256 i = pcgEngine.getMinCardPurchaseLimit(); i < pcgEngine.getMaxCardPurchaseLimit(); i++) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
            uint256 pcgId = pcgFactory.getPcgCounter() - 1;
            uint32 numberOfCards = uint32(i);
            (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
            vm.recordLogs();
            vm.prank(CONSUMER);
            pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            bytes32 requestIdBytes = entries[1].topics[1];
            if (block.chainid == 31337) {
                uint256[] memory wordsArray = new uint256[](0);
                vrfWrapper.triggerFulfillRandomness(uint256(requestIdBytes), wordsArray);
                vm.expectRevert(
                    abi.encodeWithSelector(
                        PCGEngine.PCGEngine__PurchaseIsAlreadyCompleted.selector, uint256(requestIdBytes)
                    )
                );
                vrfWrapper.triggerFulfillRandomness(uint256(requestIdBytes), wordsArray);
            } else {
                uint256[] memory wordsArray = new uint256[](i);
                for (uint256 j = 0; j < i; j++) {
                    wordsArray[j] = 100 + i;
                }

                vm.prank(address(vrfWrapper));
                pcgEngine.rawFulfillRandomWords(uint256(requestIdBytes), wordsArray);
                vm.expectRevert(
                    abi.encodeWithSelector(
                        PCGEngine.PCGEngine__PurchaseIsAlreadyCompleted.selector, uint256(requestIdBytes)
                    )
                );
                vm.prank(address(vrfWrapper));
                pcgEngine.rawFulfillRandomWords(uint256(requestIdBytes), wordsArray);
            }
        }
    }

    function test_PCGEngine_fulfillRandomWords_mintsSingleCard()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        uint256 pcgId = pcgFactory.getPcgCounter() - 1;
        uint32 numberOfCards = 1;
        (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
        vm.recordLogs();
        vm.prank(CONSUMER);
        pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestIdBytes = entries[1].topics[1];

        uint256[] memory wordsArray = new uint256[](1);
        wordsArray[0] = 21; // 21 % 10 = 1 and that is the card Id
        uint256 expectedCardId = wordsArray[0] % NUMBER_OF_MINTABLE_CARDS;
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(pcgEngine), address(0), CONSUMER, expectedCardId, 1); //amount will always be 1
        if (block.chainid == 31337) {
            vrfWrapper.triggerFulfillRandomness(uint256(requestIdBytes), wordsArray);
        } else {
            vm.prank(address(vrfWrapper));
            pcgEngine.rawFulfillRandomWords(uint256(requestIdBytes), wordsArray);
        }
    }

    function test_PCGEngine_fulfillRandomWords_mintsMultipleCards()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        for (uint256 i = 2; i <= pcgEngine.getMaxCardPurchaseLimit(); i++) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
            uint256 pcgId = pcgFactory.getPcgCounter() - 1;
            uint32 numberOfCards = uint32(i);
            (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
            vm.recordLogs();
            vm.prank(CONSUMER);
            pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            bytes32 requestIdBytes = entries[1].topics[1];

            uint256[] memory wordsArray = new uint256[](i);
            uint256[] memory amounts = new uint256[](i);
            for (uint256 j = 0; j < i; j++) {
                // i=2 ids=(0, 1)
                // i=3 ids=(0, 1, 2)
                wordsArray[j] = j;
                //amounts will always be 1
                amounts[j] = 1;
            }
            vm.expectEmit(true, true, true, true);
            emit TransferBatch(address(pcgEngine), address(0), CONSUMER, wordsArray, amounts);
            if (block.chainid == 31337) {
                vrfWrapper.triggerFulfillRandomness(uint256(requestIdBytes), wordsArray);
            } else {
                vm.prank(address(vrfWrapper));
                pcgEngine.rawFulfillRandomWords(uint256(requestIdBytes), wordsArray);
            }
        }
    }

    function test_PCGEngine_fulfillRandomWords_purchaseIsNotPendingAfterFulfillment()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        for (uint256 i = pcgEngine.getMinCardPurchaseLimit(); i <= pcgEngine.getMaxCardPurchaseLimit(); i++) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
            uint256 pcgId = pcgFactory.getPcgCounter() - 1;
            uint32 numberOfCards = uint32(i);
            (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
            vm.recordLogs();
            vm.prank(CONSUMER);
            pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            bytes32 requestIdBytes = entries[1].topics[1];
            (,, bool pendingBeforFulfillment) = pcgEngine.getPurchase(uint256(requestIdBytes));
            assertEq(pendingBeforFulfillment, true);
            uint256[] memory wordsArray = new uint256[](i);
            uint256[] memory amounts = new uint256[](i);
            for (uint256 j = 0; j < i; j++) {
                // i=1 ids=(0)
                // i=2 ids=(0, 1)
                // i=3 ids=(0, 1, 2)
                wordsArray[j] = j;
                //amounts will always be 1
                amounts[j] = 1;
            }
            if (block.chainid == 31337) {
                vrfWrapper.triggerFulfillRandomness(uint256(requestIdBytes), wordsArray);
            } else {
                vm.prank(address(vrfWrapper));
                pcgEngine.rawFulfillRandomWords(uint256(requestIdBytes), wordsArray);
            }
            (,, bool pendingAfterFulfillment) = pcgEngine.getPurchase(uint256(requestIdBytes));
            assertEq(pendingAfterFulfillment, false);
        }
    }

    function test_PCGEngine_fulfillRandomWords_event_PCGCardsPurchaseFullfilled_isEmited()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        for (uint256 i = pcgEngine.getMinCardPurchaseLimit(); i <= pcgEngine.getMaxCardPurchaseLimit(); i++) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
            uint256 pcgId = pcgFactory.getPcgCounter() - 1;
            uint32 numberOfCards = uint32(i);
            (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
            vm.recordLogs();
            vm.prank(CONSUMER);
            pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            bytes32 requestIdBytes = entries[1].topics[1];
            (,, bool pendingBeforFulfillment) = pcgEngine.getPurchase(uint256(requestIdBytes));
            assertEq(pendingBeforFulfillment, true);
            uint256[] memory wordsArray = new uint256[](i);
            uint256[] memory amounts = new uint256[](i);
            for (uint256 j = 0; j < i; j++) {
                // i=1 ids=(0)
                // i=2 ids=(0, 1)
                // i=3 ids=(0, 1, 2)
                wordsArray[j] = j;
                //amounts will always be 1
                amounts[j] = 1;
            }
            vm.expectEmit(true, true, true, false);
            emit PCGCardsPurchaseFullfilled(uint256(requestIdBytes), CONSUMER, address(pcg));
            if (block.chainid == 31337) {
                vrfWrapper.triggerFulfillRandomness(uint256(requestIdBytes), wordsArray);
            } else {
                vm.prank(address(vrfWrapper));
                pcgEngine.rawFulfillRandomWords(uint256(requestIdBytes), wordsArray);
            }
        }
    }

    function test_PCGEngine_fulfillRandomWords_event_cardBalanceIsUpdated()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        for (uint256 i = pcgEngine.getMinCardPurchaseLimit(); i <= pcgEngine.getMaxCardPurchaseLimit(); i++) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
            uint256 pcgId = pcgFactory.getPcgCounter() - 1;
            uint32 numberOfCards = uint32(i);
            (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
            vm.recordLogs();
            vm.prank(CONSUMER);
            pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            bytes32 requestIdBytes = entries[1].topics[1];
            (,, bool pendingBeforFulfillment) = pcgEngine.getPurchase(uint256(requestIdBytes));
            assertEq(pendingBeforFulfillment, true);
            uint256[] memory wordsArray = new uint256[](i);
            uint256[] memory amounts = new uint256[](i);
            address[] memory currentConsumers = new address[](i);
            for (uint256 j = 0; j < i; j++) {
                // i=1 ids=(0)
                // i=2 ids=(0, 1)
                // i=3 ids=(0, 1, 2)
                wordsArray[j] = j;
                //amounts will always be 1
                amounts[j] = 1;
                currentConsumers[j] = CONSUMER;
            }
            uint256[] memory balancesBefore = pcg.balanceOfBatch(currentConsumers, wordsArray);
            if (block.chainid == 31337) {
                vrfWrapper.triggerFulfillRandomness(uint256(requestIdBytes), wordsArray);
            } else {
                vm.prank(address(vrfWrapper));
                pcgEngine.rawFulfillRandomWords(uint256(requestIdBytes), wordsArray);
            }
            uint256[] memory balancesAfter = pcg.balanceOfBatch(currentConsumers, wordsArray);
            for (uint256 j = 0; j < balancesAfter.length; j++) {
                assert(balancesBefore[j] < balancesAfter[j]);
            }
        }
    }

    modifier deployPcgExpansion(string memory _uri, uint256 _numberOfMintableCards) {
        vm.prank(pcgFactory.owner());
        pcgFactory.deployPCGExpansion(_uri, _numberOfMintableCards);
        pcg = PCG(pcgFactory.getPcg(pcgFactory.getPcgCounter() - 1));
        _;
    }
}
