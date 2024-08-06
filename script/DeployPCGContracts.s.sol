// // SPDX-License-Identifier: MIT

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {PCGFactory} from "../src/PCGFactory.sol";
import {PCGEngine} from "../src/PCGEngine.sol";
import {IVRFV2PlusWrapper} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFV2PlusWrapper.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

pragma solidity ^0.8.20;

contract DeployPCGContracts is Script {
    error DeployPCGContracts__InvalidAddress(address _invalidAddress);

    PCGEngine private s_pcgEngine;
    PCGFactory private s_pcgFactory;

    function run() external returns (PCGEngine, PCGFactory, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address vrfWrapperAddress,
            uint32 callbackGasLimit,
            address nativeToUsdPriceFeedAddress,
            address eurToUsdPriceFeedAddress,
            address deployerAddress
        ) = helperConfig.getNetworkConfig();
        console.log("Checking if addresses are valid...");
        vm.startBroadcast(deployerAddress);
        s_pcgFactory =
            new PCGFactory(vrfWrapperAddress, callbackGasLimit, nativeToUsdPriceFeedAddress, eurToUsdPriceFeedAddress);
        vm.stopBroadcast();
        console.log("Broadcast was successful. PCG Contracts are deployed");
        s_pcgEngine = PCGEngine(s_pcgFactory.getPcgEngine());
        return (s_pcgEngine, s_pcgFactory, helperConfig);
    }
}
