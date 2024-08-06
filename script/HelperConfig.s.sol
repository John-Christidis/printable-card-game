    // SPDX-License-Identifier: MIT

import {Script, console} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {VRFWrapperMock} from "../test/mocks/VRFWrapperMock.sol";

pragma solidity ^0.8.20;

contract HelperConfig is Script {
    uint32 public CALLBACK_GAS_LIMIT = 200_000; // tested
    uint8 public NATIVE_TO_USD_DECIMALS = 8;
    int256 public NATIVE_TO_USD_PRICE = 3000_0000_0000;

    uint8 public EUR_TO_USD_DECIMALS = 8;
    int256 public EUR_TO_USD_PRICE = 1_0000_0000;

    struct NetworkConfig {
        address vrfWrapperAddress;
        uint32 callbackGasLimit;
        address nativeToUsdPriceFeedAddress;
        address eurToUsdPriceFeedAddress;
        address deployerAddress;
    }

    NetworkConfig private s_activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            console.log("Using Sepolia Configuration");
            s_activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 80002) {
            console.log("Using Amoy Configuration");
            s_activeNetworkConfig = getAmoyPolygonConfig();
        } else {
            console.log("Using Anvil Configuration");
            s_activeNetworkConfig = getAndDeployAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaNetworkConfig = NetworkConfig({
            vrfWrapperAddress: vm.envAddress("SEPOLIA_VRF_WRAPPER_ADDRESS"),
            callbackGasLimit: CALLBACK_GAS_LIMIT, //tested
            nativeToUsdPriceFeedAddress: vm.envAddress("SEPOLIA_NATIVE_TO_USD_PRICEFEED_ADDRESS"),
            eurToUsdPriceFeedAddress: vm.envAddress("SEPOLIA_EUR_TO_USD_PRICEFEED_ADDRESS"),
            deployerAddress: vm.envAddress("SEPOLIA_DEPLOYER_ADDRESS")
        });

        return sepoliaNetworkConfig;
    }

    function getAmoyPolygonConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory amoyNetworkConfig = NetworkConfig({
            vrfWrapperAddress: vm.envAddress("AMOY_VRF_WRAPPER_ADDRESS"),
            callbackGasLimit: CALLBACK_GAS_LIMIT,
            nativeToUsdPriceFeedAddress: vm.envAddress("AMOY_NATIVE_TO_USD_PRICEFEED_ADDRESS"),
            eurToUsdPriceFeedAddress: vm.envAddress("AMOY_EUR_TO_USD_PRICEFEED_ADDRESS"),
            deployerAddress: vm.envAddress("AMOY_DEPLOYER_ADDRESS")
        });

        return amoyNetworkConfig;
    }

    function getAndDeployAnvilEthConfig() public returns (NetworkConfig memory) {
        if (s_activeNetworkConfig.vrfWrapperAddress != address(0)) {
            return s_activeNetworkConfig;
        }
        vm.startBroadcast(vm.envAddress("ANVIL_DEPLOYER_ADDRESS"));
        VRFWrapperMock vrfWrapper = new VRFWrapperMock();
        MockV3Aggregator nativeMockToUsdAggregator = new MockV3Aggregator(NATIVE_TO_USD_DECIMALS, NATIVE_TO_USD_PRICE);
        MockV3Aggregator eurToUsdAggregator = new MockV3Aggregator(EUR_TO_USD_DECIMALS, EUR_TO_USD_PRICE);
        vm.stopBroadcast();

        NetworkConfig memory anvilNetworkConfig = NetworkConfig({
            vrfWrapperAddress: address(vrfWrapper),
            callbackGasLimit: CALLBACK_GAS_LIMIT,
            nativeToUsdPriceFeedAddress: address(nativeMockToUsdAggregator),
            eurToUsdPriceFeedAddress: address(eurToUsdAggregator),
            deployerAddress: vm.envAddress("ANVIL_DEPLOYER_ADDRESS")
        });

        return anvilNetworkConfig;
    }

    function getNetworkConfig() public view returns (address, uint32, address, address, address) {
        return (
            s_activeNetworkConfig.vrfWrapperAddress,
            s_activeNetworkConfig.callbackGasLimit,
            s_activeNetworkConfig.nativeToUsdPriceFeedAddress,
            s_activeNetworkConfig.eurToUsdPriceFeedAddress,
            s_activeNetworkConfig.deployerAddress
        );
    }
}
