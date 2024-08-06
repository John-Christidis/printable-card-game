//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployPCGExpansion} from "../../../script/DeployPCGExpansion.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {DeployPCGContracts} from "../../../script/DeployPCGContracts.s.sol";
import {PCG} from "../../../src/PCG.sol";
import {PCGFactory} from "../../../src/PCGFactory.sol";

import {PCGEngine} from "../../../src/PCGEngine.sol";

contract DeployPCGExpansionTest is Test {
    DeployPCGExpansion deployer;
    PCGFactory pcgFactory;
    uint256 zeroNumberOfCards = 0;
    uint256 validNumberOfCards = 1;
    string emptyUri = "";
    string cid = "test";
    string differentCid = "different-test";

    function setUp() external {
        DeployPCGContracts deployerOfContracts = new DeployPCGContracts();
        (, pcgFactory,) = deployerOfContracts.run();
        deployer = new DeployPCGExpansion();
    }

    function test_DeployPCGExpansion_failsIfNumberOfMintableCardsIsZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployPCGExpansion.DeployPCGExpansion__InvalidNumberOfMintableCards.selector, zeroNumberOfCards
            )
        );
        deployer.run(address(pcgFactory), cid, zeroNumberOfCards);
    }

    function test_DeployPCGExpansion_failsIfCidIsEmpty() external {
        vm.expectRevert(abi.encodeWithSelector(DeployPCGExpansion.DeployPCGExpansion__CIDIsEmpty.selector));
        deployer.run(address(pcgFactory), emptyUri, validNumberOfCards);
    }

    function test_DeployPCGExpansion_failsIfCidIsAlreadyUsed() external {
        string memory uri = string.concat("ipfs://", cid, "/{id}.json");
        deployer.run(address(pcgFactory), cid, validNumberOfCards);
        vm.expectRevert(abi.encodeWithSelector(DeployPCGExpansion.DeployPCGExpansion__URIAlreadyUsed.selector, uri));
        deployer.run(address(pcgFactory), cid, validNumberOfCards);
    }

    function test_DeployPCGExpansion_worksAsIntended() external {
        deployer.run(address(pcgFactory), cid, validNumberOfCards);
        deployer.run(address(pcgFactory), differentCid, validNumberOfCards);
    }
}
