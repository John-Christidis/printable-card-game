//SPDX-License-Identifier: MIT

// Invariants

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Vm} from "forge-std/Vm.sol";

import {PCGFactory} from "../../../src/PCGFactory.sol";
import {PCGEngine} from "../../../src/PCGEngine.sol";
import {PCG} from "../../../src/PCG.sol";
import {PriceConverter} from "../../../src/libraries/PriceConverter.sol";

import {VRFWrapperMock} from "../../mocks/VRFWrapperMock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {DeployPCGContracts} from "../../../script/DeployPCGContracts.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";

import {Strings} from "@openzeppelin/utils/Strings.sol";

contract Handler is Test {
    using Strings for uint256;
    using PriceConverter for uint256;

    PCGFactory pcgFactory;
    PCGEngine pcgEngine;
    PCG[] pcgs;

    VRFWrapperMock vrfWrapper;

    MockV3Aggregator nativeToUsdPriceFeed;
    MockV3Aggregator eurToUsdPriceFeed;

    address[] consumers;
    uint256 public CONSUMER_BALANCE = 100 ether;

    //These two need change for all cases
    int256 public MAX_PRICE_SIZE = type(int96).max; //big number but it cannot break the system
    int256 public MIN_PRICE_SIZE = type(int96).min;

    uint256 public purchasePcgCards_failedAttemps;
    uint256 public withdraw_failedAttempts;
    uint256 public fulfillPcgCards_failedAttemps;
    uint256 public estimateCardsPrice_failedAttempts;

    uint256[] public purchases;

    mapping(uint256 _purchaseId => uint32 _numberOfCards) public numberOfCardsPurchased;

    constructor(
        PCGEngine _pcgEngine,
        PCGFactory _pcgFactory,
        PCG[] memory _pcgs,
        VRFWrapperMock _vrfWrapper,
        MockV3Aggregator _nativeToUsdPriceFeed,
        MockV3Aggregator _eurToUsdPriceFeed
    ) {
        pcgEngine = _pcgEngine;
        pcgFactory = _pcgFactory;
        for (uint256 i = 0; i < _pcgs.length; i++) {
            pcgs.push(_pcgs[i]);
        }
        vrfWrapper = _vrfWrapper;
        nativeToUsdPriceFeed = _nativeToUsdPriceFeed;
        eurToUsdPriceFeed = _eurToUsdPriceFeed;
        for (uint256 i = 0; i < 10; i++) {
            consumers.push(makeAddr(i.toString()));
            vm.deal(consumers[i], CONSUMER_BALANCE);
        }
        purchasePcgCards_failedAttemps = 0;
        fulfillPcgCards_failedAttemps = 0;
    }

    function purchasePcgCards(
        uint256 _pcgId,
        uint256 _numberOfCards,
        int256 _newNativeToUsdPrice,
        int256 _newEurToUsdPrice,
        uint96 _gasPricePerGas,
        uint256 _consumerId
    ) external {
        _pcgId = bound(_pcgId, 0, pcgFactory.getPcgCounter() - 1);
        _numberOfCards = bound(_numberOfCards, pcgEngine.getMinCardPurchaseLimit(), pcgEngine.getMaxCardPurchaseLimit());
        _consumerId = bound(_consumerId, 0, consumers.length - 1);
        _newNativeToUsdPrice = bound(_newNativeToUsdPrice, MIN_PRICE_SIZE, MAX_PRICE_SIZE);
        _newEurToUsdPrice = bound(_newEurToUsdPrice, MIN_PRICE_SIZE, MAX_PRICE_SIZE);

        if (block.chainid == 31337) {
            nativeToUsdPriceFeed.updateAnswer(_newNativeToUsdPrice);
            eurToUsdPriceFeed.updateAnswer(_newEurToUsdPrice);
        }

        (,,, uint256 totalPrice) = pcgEngine.estimatePcgCardsPrice(uint32(_numberOfCards), _gasPricePerGas);
        // 171_452 from anvil gas report  210_910 from sepolia gas report
        uint256 gasCostForPurchase = 250_000;
        uint256 gasPrice = _gasPricePerGas * gasCostForPurchase;
        vm.deal(consumers[_consumerId], totalPrice + 1 + gasPrice);
        vm.txGasPrice(_gasPricePerGas);
        vm.recordLogs();
        vm.startPrank(consumers[_consumerId]);
        try pcgEngine.purchasePcgCards{value: totalPrice + 1}(_pcgId, uint32(_numberOfCards)) {
            vm.stopPrank();
            Vm.Log[] memory entries = vm.getRecordedLogs();
            bytes32 requestIdBytes = entries[1].topics[1];
            purchases.push(uint256(requestIdBytes));
            numberOfCardsPurchased[uint256(requestIdBytes)] = uint32(_numberOfCards);
        } catch {
            vm.stopPrank();
            purchasePcgCards_failedAttemps++;
        }
    }

    function fulfillPcgPurchase(uint256 _purchasePointer, uint256[] memory _randomNumbers) external {
        if (purchases.length != 0) {
            _purchasePointer = bound(_purchasePointer, 0, purchases.length - 1);
            uint256 purchaseId = purchases[_purchasePointer];
            uint32 numberOfCards = numberOfCardsPurchased[purchaseId];
            vm.assume(_randomNumbers.length >= numberOfCards);
            uint256[] memory boundedRandomNumbers = new uint256[](numberOfCards);
            for (uint256 i = 0; i < numberOfCards; i++) {
                boundedRandomNumbers[i] = _randomNumbers[i];
            }
            if (block.chainid == 31337) {
                try vrfWrapper.triggerFulfillRandomness(purchaseId, boundedRandomNumbers) {}
                catch (bytes memory reason) {
                    bytes4 expectedError = PCGEngine.PCGEngine__PurchaseIsAlreadyCompleted.selector;
                    bytes4 receivedError = bytes4(reason);
                    if (receivedError != expectedError) {
                        fulfillPcgCards_failedAttemps++;
                    }
                }
            } else {
                vm.startPrank(address(vrfWrapper));
                try pcgEngine.rawFulfillRandomWords(purchaseId, boundedRandomNumbers) {}
                catch (bytes memory reason) {
                    bytes4 expectedError = PCGEngine.PCGEngine__PurchaseIsAlreadyCompleted.selector;
                    bytes4 receivedError = bytes4(reason);
                    if (receivedError != expectedError) {
                        fulfillPcgCards_failedAttemps++;
                    }
                }
            }
        }
    }

    function estimateCardsPrice(uint32 _numberOfCards, uint96 _gasPrice) public {
        try pcgEngine.estimatePcgCardsPrice(_numberOfCards, _gasPrice) returns (uint32, uint256, uint256, uint256) {}
        catch {
            estimateCardsPrice_failedAttempts++;
        }
    }

    function getPurchasesSize() public view returns (uint256) {
        return purchases.length;
    }
}
