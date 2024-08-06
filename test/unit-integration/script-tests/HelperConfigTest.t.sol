//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PCGFactory} from "../../../src/PCGFactory.sol";
import {PCG} from "../../../src/PCG.sol";
import {PCGEngine} from "../../../src/PCGEngine.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {VRFWrapperMock} from "../../mocks/VRFWrapperMock.sol";
import {FakePCGFactoryOwnerMock} from "../../mocks/FakePCGFactoryOwnerMock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {DeployPCGContracts} from "../../../script/DeployPCGContracts.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {PriceConverter} from "../../../src/libraries/PriceConverter.sol";

contract HelperConfigTest is Test {
    HelperConfig helperConfig;

    uint32 public CALLBACK_GAS_LIMIT = 200_000; // tested
    uint8 public NATIVE_TO_USD_DECIMALS = 8;
    int256 public NATIVE_TO_USD_PRICE = 3000_0000_0000;

    uint8 public EUR_TO_USD_DECIMALS = 8;
    int256 public EUR_TO_USD_PRICE = 1_0000_0000;

    function setUp() external {
        helperConfig = new HelperConfig();
    }

    function test_HelperConfig_constructor_variables() external {
        (
            address vrfWrapperAddress,
            uint32 callbackGasLimit,
            address nativeToUsdPriceFeedAddress,
            address eurToUsdPriceFeedAddress,
            address deployerAddress
        ) = helperConfig.getNetworkConfig();

        if (block.chainid == 11155111) {
            HelperConfig.NetworkConfig memory sepoliaNetworkConfig = helperConfig.getSepoliaEthConfig();
            assertEq(sepoliaNetworkConfig.vrfWrapperAddress, vrfWrapperAddress);
            assertEq(sepoliaNetworkConfig.callbackGasLimit, callbackGasLimit);
            assertEq(sepoliaNetworkConfig.nativeToUsdPriceFeedAddress, nativeToUsdPriceFeedAddress);
            assertEq(sepoliaNetworkConfig.eurToUsdPriceFeedAddress, eurToUsdPriceFeedAddress);
            assertEq(sepoliaNetworkConfig.deployerAddress, deployerAddress);
        } else if (block.chainid == 80002) {
            HelperConfig.NetworkConfig memory amoyNetworkConfig = helperConfig.getAmoyPolygonConfig();
            assertEq(amoyNetworkConfig.vrfWrapperAddress, vrfWrapperAddress);
            assertEq(amoyNetworkConfig.callbackGasLimit, callbackGasLimit);
            assertEq(amoyNetworkConfig.nativeToUsdPriceFeedAddress, nativeToUsdPriceFeedAddress);
            assertEq(amoyNetworkConfig.eurToUsdPriceFeedAddress, eurToUsdPriceFeedAddress);
            assertEq(amoyNetworkConfig.deployerAddress, deployerAddress);
        } else {
            HelperConfig.NetworkConfig memory anvilNetworkConfig = helperConfig.getAndDeployAnvilEthConfig();
            assertEq(anvilNetworkConfig.vrfWrapperAddress, vrfWrapperAddress);
            assertEq(anvilNetworkConfig.callbackGasLimit, callbackGasLimit);
            assertEq(anvilNetworkConfig.nativeToUsdPriceFeedAddress, nativeToUsdPriceFeedAddress);
            assertEq(anvilNetworkConfig.eurToUsdPriceFeedAddress, eurToUsdPriceFeedAddress);
            assertEq(anvilNetworkConfig.deployerAddress, deployerAddress);
        }

        assert(vrfWrapperAddress != address(0));
        assertEq(callbackGasLimit, CALLBACK_GAS_LIMIT);
        assert(nativeToUsdPriceFeedAddress != address(0));
        assert(eurToUsdPriceFeedAddress != address(0));
    }

    function test_HelperConfig_getSepoliaEthConfig() public {
        // Simulate Sepolia network (chain ID 11155111)
        vm.chainId(11155111);
        helperConfig = new HelperConfig();

        (
            address vrfWrapperAddress,
            uint32 callbackGasLimit,
            address nativeToUsdPriceFeedAddress,
            address eurToUsdPriceFeedAddress,
            address deployerAddress
        ) = helperConfig.getNetworkConfig();

        assertEq(vrfWrapperAddress, vm.envAddress("SEPOLIA_VRF_WRAPPER_ADDRESS"));
        assertEq(callbackGasLimit, CALLBACK_GAS_LIMIT);
        assertEq(nativeToUsdPriceFeedAddress, vm.envAddress("SEPOLIA_NATIVE_TO_USD_PRICEFEED_ADDRESS"));
        assertEq(eurToUsdPriceFeedAddress, vm.envAddress("SEPOLIA_EUR_TO_USD_PRICEFEED_ADDRESS"));
        assertEq(deployerAddress, vm.envAddress("SEPOLIA_DEPLOYER_ADDRESS"));
        //}
    }

    function test_HelperConfig_getAmoyPolygonConfig() public {
        // Simulate Amoy Polygon network (chain ID 80002)
        vm.chainId(80002);
        helperConfig = new HelperConfig();

        (
            address vrfWrapperAddress,
            uint32 callbackGasLimit,
            address nativeToUsdPriceFeedAddress,
            address eurToUsdPriceFeedAddress,
            address deployerAddress
        ) = helperConfig.getNetworkConfig();

        assertEq(vrfWrapperAddress, vm.envAddress("AMOY_VRF_WRAPPER_ADDRESS"));
        assertEq(callbackGasLimit, CALLBACK_GAS_LIMIT);
        assertEq(nativeToUsdPriceFeedAddress, vm.envAddress("AMOY_NATIVE_TO_USD_PRICEFEED_ADDRESS"));
        assertEq(eurToUsdPriceFeedAddress, vm.envAddress("AMOY_EUR_TO_USD_PRICEFEED_ADDRESS"));
        assertEq(deployerAddress, vm.envAddress("AMOY_DEPLOYER_ADDRESS"));
        //}
    }

    function test_HelperConfig_getAndDeployAnvilEthConfig() public {
        // Simulate Anvil (local network)
        vm.chainId(31337);
        helperConfig = new HelperConfig();

        (
            address vrfWrapperAddress,
            uint32 callbackGasLimit,
            address nativeToUsdPriceFeedAddress,
            address eurToUsdPriceFeedAddress,
            address deployerAddress
        ) = helperConfig.getNetworkConfig();

        assertEq(callbackGasLimit, CALLBACK_GAS_LIMIT);
        assertEq(deployerAddress, vm.envAddress("ANVIL_DEPLOYER_ADDRESS"));

        assertTrue(vrfWrapperAddress != address(0));
        assertTrue(nativeToUsdPriceFeedAddress != address(0));
        assertTrue(eurToUsdPriceFeedAddress != address(0));
    }
}
