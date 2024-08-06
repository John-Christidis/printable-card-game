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

contract OpenHandler is Test {
    using Strings for uint256;
    using PriceConverter for uint256;

    PCGFactory pcgFactory;
    PCGEngine pcgEngine;
    PCG[] pcgs;

    address[] consumers;

    uint256 public estimateCardsPrice_failedAttempts;

    constructor(PCGEngine _pcgEngine, PCGFactory _pcgFactory, PCG[] memory _pcgs) {
        pcgEngine = _pcgEngine;
        pcgFactory = _pcgFactory;
        for (uint256 i = 0; i < _pcgs.length; i++) {
            pcgs.push(_pcgs[i]);
        }

        for (uint256 i = 0; i < 10; i++) {
            consumers.push(makeAddr(i.toString()));
        }
    }

    function purchasePcgCards_testing_freeMsgValue(
        uint256 _pcgId,
        uint256 _numberOfCards,
        uint256 _consumerId,
        uint256 _msgValue
    ) external {
        _pcgId = bound(_pcgId, 0, pcgFactory.getPcgCounter() - 1);
        _numberOfCards = bound(_numberOfCards, pcgEngine.getMinCardPurchaseLimit(), pcgEngine.getMaxCardPurchaseLimit());
        _consumerId = bound(_consumerId, 0, consumers.length - 1);

        vm.deal(consumers[_consumerId], _msgValue);
        vm.recordLogs();
        vm.prank(consumers[_consumerId]);
        pcgEngine.purchasePcgCards{value: _msgValue}(_pcgId, uint32(_numberOfCards));
    }

    function estimateCardsPrice(uint32 _numberOfCards, uint96 _gasPrice) public {
        try pcgEngine.estimatePcgCardsPrice(_numberOfCards, _gasPrice) returns (uint32, uint256, uint256, uint256) {}
        catch {
            estimateCardsPrice_failedAttempts++;
        }
    }
}
