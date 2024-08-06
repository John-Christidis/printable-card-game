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
import {MaliciousPCGFactoryOwnerVRFWrapperMock} from "../../mocks/MaliciousPCGFactoryOwnerVRFWrapperMock.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PCGEngineConstructorTest is Test {
    using PriceConverter for uint256;

    PCGFactory pcgFactory;
    PCGEngine pcgEngine;

    VRFWrapperMock vrfWrapper;
    MockV3Aggregator nativeToUsdPriceFeed;
    MockV3Aggregator eurToUsdPriceFeed;

    uint32 callbackGasLimit;
    uint16 public REQUEST_CONFIRMATIONS = 3;
    uint32 public CARD_PURCHASE_LIMIT = 3;
    uint256 public CARD_PRICE_EUR = 2 * 10 ** 18;
    uint256 public STANDARD_TX_GUS_PRICE = 50_000_000_000;

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

    function test_PCGEngine_withdraw_reentrancyAttack() external {
        MaliciousPCGFactoryOwnerVRFWrapperMock mal = new MaliciousPCGFactoryOwnerVRFWrapperMock();
        uint256 malBalance = 3 ether;

        vm.startPrank(address(mal));
        PCGFactory malPcgFactory =
            new PCGFactory(address(mal), callbackGasLimit, address(nativeToUsdPriceFeed), address(eurToUsdPriceFeed));
        PCGEngine hackedPcgEngine = PCGEngine(malPcgFactory.getPcgEngine());
        mal.setPcgEngine(address(hackedPcgEngine));
        string memory uri = "";
        uint256 numberOfMintableCards = 10;
        malPcgFactory.deployPCGExpansion(uri, numberOfMintableCards);
        vm.deal(address(mal), malBalance);
        vm.txGasPrice(STANDARD_TX_GUS_PRICE);
        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        hackedPcgEngine.purchasePcgCards{value: 2 ether}(0, 3);
        vm.stopPrank();
    }
}
