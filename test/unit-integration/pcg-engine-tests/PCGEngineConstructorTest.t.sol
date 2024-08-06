//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PCGFactory} from "../../../src/PCGFactory.sol";
import {PCGEngine} from "../../../src/PCGEngine.sol";
import {PriceConverter} from "../../../src/libraries/PriceConverter.sol";
import {VRFWrapperMock} from "../../mocks/VRFWrapperMock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {DeployPCGContracts} from "../../../script/DeployPCGContracts.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";

contract PCGEngineConstructorTest is Test {
    using PriceConverter for uint256;

    PCGFactory pcgFactory;
    PCGEngine pcgEngine;

    VRFWrapperMock vrfWrapper;
    MockV3Aggregator nativeToUsdPriceFeed;
    MockV3Aggregator eurToUsdPriceFeed;

    uint32 callbackGasLimit;
    uint16 public REQUEST_CONFIRMATIONS = 3;
    uint32 public MIN_CARD_PURCHASE_LIMIT = 1;
    uint32 public MAX_CARD_PURCHASE_LIMIT = 3;
    uint256 public CARD_PRICE_EUR = 2 * 10 ** 18;

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
    }

    function test_PCGEngine_constructor_vrfWrapperRevertsIfNotValid() external {
        address randomAddress = makeAddr("random");
        vm.expectRevert();
        new PCGEngine(
            randomAddress,
            callbackGasLimit,
            address(nativeToUsdPriceFeed),
            address(eurToUsdPriceFeed),
            address(pcgFactory)
        );
    }

    function test_PCGEngine_constructor_successfulyDeployed() external {
        PCGEngine newPcgEngine = new PCGEngine(
            address(vrfWrapper),
            callbackGasLimit,
            address(nativeToUsdPriceFeed),
            address(eurToUsdPriceFeed),
            address(pcgFactory)
        );
        assert(address(newPcgEngine) != address(0));
    }

    function test_PCGEngine_constructor_variablesSetUpCorrectly() external view {
        (address contractVrfWrapper, uint32 contractCallbackGasLimit, uint16 contractRequestConfirmations) =
            pcgEngine.getVrfConfig();
        assertEq(contractVrfWrapper, address(vrfWrapper));
        assertEq(contractCallbackGasLimit, callbackGasLimit);
        assertEq(contractRequestConfirmations, REQUEST_CONFIRMATIONS);
        (address contractNativeToUsdPriceFeedAddress, address contractEurToUsdPriceFeedAddress) =
            pcgEngine.getPriceFeedAddresses();
        assertEq(contractNativeToUsdPriceFeedAddress, address(nativeToUsdPriceFeed));
        assertEq(contractEurToUsdPriceFeedAddress, address(eurToUsdPriceFeed));
        assertEq(pcgEngine.getPcgFactoryAddress(), address(pcgFactory));
        (, uint256 currentPriceConversion) =
            CARD_PRICE_EUR.getConversionRate(address(nativeToUsdPriceFeed), address(eurToUsdPriceFeed), 0);
        assertEq(pcgEngine.getLastPriceConverstion(), currentPriceConversion);
        assertEq(pcgEngine.getMinCardPurchaseLimit(), MIN_CARD_PURCHASE_LIMIT);
        assertEq(pcgEngine.getMaxCardPurchaseLimit(), MAX_CARD_PURCHASE_LIMIT);
        assertEq(pcgEngine.getCardPrice(), CARD_PRICE_EUR);
    }
}
