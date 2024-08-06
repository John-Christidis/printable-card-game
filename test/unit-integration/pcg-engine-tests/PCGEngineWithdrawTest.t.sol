//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PCGFactory} from "../../../src/PCGFactory.sol";
import {PCG} from "../../../src/PCG.sol";
import {PCGEngine} from "../../../src/PCGEngine.sol";
import {FakePCGFactoryOwnerMock} from "../../mocks/FakePCGFactoryOwnerMock.sol";

import {DeployPCGContracts} from "../../../script/DeployPCGContracts.s.sol";

contract PCGEngineWithdrawTest is Test {
    PCGFactory pcgFactory;
    PCGEngine pcgEngine;
    PCG pcg;

    uint32 public CARD_PURCHASE_LIMIT = 3;
    uint256 public CARD_PRICE_EUR = 2 * 10 ** 18;

    string public URI = "http://test/id:{id}";
    uint256 public NUMBER_OF_MINTABLE_CARDS = 10;
    uint256 public STANDARD_TX_GUS_PRICE = 50_000_000_000;

    address public CONSUMER = makeAddr("consumer");
    uint256 public CONSUMER_BALANCE = 100 ether;

    function setUp() external {
        DeployPCGContracts deployer = new DeployPCGContracts();
        (pcgEngine, pcgFactory,) = deployer.run();
        vm.deal(CONSUMER, CONSUMER_BALANCE);
    }

    function test_PCGEngine_withdraw_canOnlyBeUsedByPCGFactoryOwner() external {
        address fakeOwner = makeAddr("fake-owner");
        vm.prank(fakeOwner);
        vm.expectRevert(
            abi.encodeWithSelector(PCGEngine.PCGEngine__OnlyPCGFactoryOwnerCanWithdrawEther.selector, fakeOwner)
        );
        pcgEngine.withdraw();
    }

    function test_PCGEngine_withdraw_PCGFactoryOwnerRecievesTheMoney()
        external
        deployPcgExpansion(URI, NUMBER_OF_MINTABLE_CARDS)
    {
        bool withGasReport = vm.envBool("WITH_GAS_REPORT");

        if (!withGasReport) {
            vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        }
        uint256 pcgId = pcgFactory.getPcgCounter() - 1;
        uint32 numberOfCards = 3;
        (,, uint256 cardsPrice, uint256 totalPrice) =
            pcgEngine.estimatePcgCardsPrice(numberOfCards, uint96(tx.gasprice));
        vm.prank(CONSUMER);
        pcgEngine.purchasePcgCards{value: totalPrice + 1}(pcgId, numberOfCards);
        uint256 ownerBalanceBeforeWithdraw = pcgFactory.owner().balance;

        vm.txGasPrice(0);
        vm.prank(pcgFactory.owner());
        pcgEngine.withdraw();
        uint256 ownerBalanceAfterWithdraw = pcgFactory.owner().balance;
        assertEq(ownerBalanceBeforeWithdraw + cardsPrice + 1, ownerBalanceAfterWithdraw);
    }

    /**
     * @dev We are using a contract fakePcgFactoryOwner with a fallback function that reverts to test this
     */
    function test_PCGEngine_withdraw_revertsWithTheCorrectErrorWhenFail() external {
        FakePCGFactoryOwnerMock fakePcgFactoryOwner = new FakePCGFactoryOwnerMock();
        vm.prank(pcgFactory.owner());
        pcgFactory.transferOwnership(address(fakePcgFactoryOwner));
        vm.prank(address(fakePcgFactoryOwner));
        vm.expectRevert(PCGEngine.PCGEngine__WithdrawFailed.selector);
        pcgEngine.withdraw();
    }

    modifier deployPcgExpansion(string memory _uri, uint256 _numberOfMintableCards) {
        vm.prank(pcgFactory.owner());
        pcgFactory.deployPCGExpansion(_uri, _numberOfMintableCards);
        pcg = PCG(pcgFactory.getPcg(pcgFactory.getPcgCounter() - 1));
        _;
    }
}
