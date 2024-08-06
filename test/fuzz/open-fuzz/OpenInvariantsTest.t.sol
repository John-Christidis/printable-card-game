//SPDX-License-Identifier: MIT

// Invariants

// 1. The last price should always be above 0
// 2. View functions should never revert

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {PCGFactory} from "../../../src/PCGFactory.sol";
import {PCGEngine} from "../../../src/PCGEngine.sol";
import {PCG} from "../../../src/PCG.sol";
import {PriceConverter} from "../../../src/libraries/PriceConverter.sol";

import {VRFWrapperMock} from "../../mocks/VRFWrapperMock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {DeployPCGContracts} from "../../../script/DeployPCGContracts.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";

import {OpenHandler} from "./OpenHandler.t.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    using PriceConverter for uint256;

    PCGFactory pcgFactory;
    PCGEngine pcgEngine;
    PCG[] pcgs;

    VRFWrapperMock vrfWrapper;
    uint32 callbackGasLimit;

    MockV3Aggregator nativeToUsdPriceFeed;
    MockV3Aggregator eurToUsdPriceFeed;

    OpenHandler handler;

    function setUp() external {
        DeployPCGContracts deployer = new DeployPCGContracts();
        HelperConfig helperConfig;
        (pcgEngine, pcgFactory, helperConfig) = deployer.run();
        (
            address configVrfWrapperAddress,
            uint32 configCallbackGasLimit,
            address configNativeToUsdPriceFeedAddress,
            address configEurToUsdPriceFeedAddress,
        ) = helperConfig.getNetworkConfig();
        callbackGasLimit = configCallbackGasLimit;
        vrfWrapper = VRFWrapperMock(configVrfWrapperAddress);
        nativeToUsdPriceFeed = MockV3Aggregator(configNativeToUsdPriceFeedAddress);
        eurToUsdPriceFeed = MockV3Aggregator(configEurToUsdPriceFeedAddress);
        uint256 expansions = 10;
        string memory uri = "http://test/id:{id}";
        uint256 startingNumberOfMintableCards = 10;
        for (uint256 i = 0; i < expansions; i++) {
            uint256 numberOfMintableCards = startingNumberOfMintableCards + i;
            vm.startPrank(pcgFactory.owner());
            pcgFactory.deployPCGExpansion(uri, numberOfMintableCards);
            vm.stopPrank();
            pcgs.push(PCG(pcgFactory.getPcg(pcgFactory.getPcgCounter() - 1)));
        }
        handler = new OpenHandler(pcgEngine, pcgFactory, pcgs);
        targetContract(address(handler));
    }

    function invariant_open_PCGEngine_lastPriceConversion_ShouldAlwaysBeAboveZero() public view {
        assert(pcgEngine.getLastPriceConverstion() > 0);
    }

    function invariant_open_PCGEngine_estimateCardsPrice_ShouldAlwaysSucceed() public view {
        console.log("failed attempts estimation: ", handler.estimateCardsPrice_failedAttempts());
        assertEq(handler.estimateCardsPrice_failedAttempts(), 0);
    }
}
