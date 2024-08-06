//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PCGFactory} from "../../src/PCGFactory.sol";
import {PCG} from "../../src/PCG.sol";
import {PCGEngine} from "../../src/PCGEngine.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {VRFWrapperMock} from "../mocks/VRFWrapperMock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract PCGFactoryTest is Test {
    event PCGExpanionDeployed(string indexed _uri, uint256 indexed _pcgId, address indexed _pcgAddress);

    PCGFactory pcgFactory;
    PCGEngine pcgEngine;
    VRFWrapperMock vrfWrapper;
    uint32 public CALLBACK_GAS_LIMIT = 200_000;
    MockV3Aggregator nativeToUsdPriceFeed;
    MockV3Aggregator eurToUsdPriceFeed;

    uint8 NATIVE_TO_USD_DECIMALS = 8;
    int256 NATIVE_TO_USD_PRICE = 3000_0000_0000;

    uint8 EUR_TO_USD_DECIMALS = 8;
    int256 EUR_TO_USD_PRICE = 1_0000_0000;

    string public URI = "http://test/id:{id}";
    uint256 public EXPANSION = 0;
    uint256 public NUMBER_OF_MINTABLE_CARDS = 10;

    function setUp() external {
        vm.startPrank(msg.sender);
        vrfWrapper = new VRFWrapperMock();
        nativeToUsdPriceFeed = new MockV3Aggregator(NATIVE_TO_USD_DECIMALS, NATIVE_TO_USD_PRICE);
        eurToUsdPriceFeed = new MockV3Aggregator(EUR_TO_USD_DECIMALS, EUR_TO_USD_PRICE);
        pcgFactory = new PCGFactory(
            address(vrfWrapper), CALLBACK_GAS_LIMIT, address(nativeToUsdPriceFeed), address(eurToUsdPriceFeed)
        );
        vm.stopPrank();
        pcgEngine = PCGEngine(pcgFactory.getPcgEngine());
    }

    function test_PCGFactory_constructor_setsVariablesCorrectly() external view {
        assertEq(pcgFactory.owner(), msg.sender);
        assertEq(pcgFactory.getPcgCounter(), 0);
        assert(pcgFactory.getPcgEngine() != address(0));
        (address natToUsdPriceFeedAddress, address eurToUsdPriceFeedAddress) = pcgEngine.getPriceFeedAddresses();
        assertEq(natToUsdPriceFeedAddress, address(nativeToUsdPriceFeed));
        assertEq(eurToUsdPriceFeedAddress, address(eurToUsdPriceFeed));
        (address vrfWrapperAddress, uint32 callbackGasLimit,) = pcgEngine.getVrfConfig();
        assertEq(vrfWrapperAddress, address(vrfWrapper));
        assertEq(callbackGasLimit, CALLBACK_GAS_LIMIT);
        assertEq(pcgEngine.getPcgFactoryAddress(), address(pcgFactory));
    }

    function test_PCGFactory_getPcg_worksAsIntendeed() external {
        vm.prank(msg.sender);
        pcgFactory.deployPCGExpansion(URI, NUMBER_OF_MINTABLE_CARDS);
        assert(pcgFactory.getPcg(0) != address(0));
    }

    function test_PCGFactory_getPcg_returnsAddressZeroOnAnUndeployedContract() external view {
        assertEq(pcgFactory.getPcg(0), address(0));
    }

    function test_PCGFactory_constructor_secondTest() external {
        vm.prank(msg.sender);
        PCGFactory newPcgFactory = new PCGFactory(
            address(vrfWrapper), CALLBACK_GAS_LIMIT, address(nativeToUsdPriceFeed), address(eurToUsdPriceFeed)
        );
        assert(newPcgFactory.getPcgEngine() != address(0));
        assertEq(newPcgFactory.owner(), msg.sender);
        assertEq(newPcgFactory.getPcgCounter(), 0);
        PCGEngine newPcgEngine = PCGEngine(newPcgFactory.getPcgEngine());
        (address natToUsdPriceFeedAddress, address eurToUsdPriceFeedAddress) = newPcgEngine.getPriceFeedAddresses();
        assertEq(natToUsdPriceFeedAddress, address(nativeToUsdPriceFeed));
        assertEq(eurToUsdPriceFeedAddress, address(eurToUsdPriceFeed));
        (address vrfWrapperAddress, uint32 callbackGasLimit,) = newPcgEngine.getVrfConfig();
        assertEq(vrfWrapperAddress, address(vrfWrapper));
        assertEq(callbackGasLimit, CALLBACK_GAS_LIMIT);
        assertEq(newPcgEngine.getPcgFactoryAddress(), address(newPcgFactory));
    }

    function test_PCGFactory_deployPCGExpansion_canOnlyBeUsedByOwner() external {
        address random = makeAddr("random");
        vm.prank(random);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, random));
        pcgFactory.deployPCGExpansion(URI, NUMBER_OF_MINTABLE_CARDS);
    }

    function test_PCGFactory_deployPCGExpansion_pcgCounterIsUpdated() external {
        uint256 prePcgCounter = pcgFactory.getPcgCounter();
        vm.prank(msg.sender);
        pcgFactory.deployPCGExpansion(URI, NUMBER_OF_MINTABLE_CARDS);
        uint256 postPcgCounter = pcgFactory.getPcgCounter();
        assertEq(prePcgCounter + 1, postPcgCounter);
    }

    function test_PCGFactory_deployPCGExpansion_pcgExpansionAddressIsSavedCorrectly() external {
        vm.prank(msg.sender);
        pcgFactory.deployPCGExpansion(URI, NUMBER_OF_MINTABLE_CARDS);
        uint256 pcgCounter = pcgFactory.getPcgCounter();
        assert(pcgFactory.getPcg(pcgCounter - 1) != address(0));
    }

    function test_PCGFactory_deployPCGExpansion_pcgExpansionDeployedSuccessfuly() external {
        vm.prank(msg.sender);
        pcgFactory.deployPCGExpansion(URI, NUMBER_OF_MINTABLE_CARDS);
        uint256 pcgCounter = pcgFactory.getPcgCounter();
        address pcgAddress = pcgFactory.getPcg(pcgCounter - 1);
        PCG pcg = PCG(pcgAddress);
        uint256 firstTokenId = 0;
        assertEq(keccak256(abi.encodePacked(pcg.uri(firstTokenId))), keccak256(abi.encodePacked(URI)));
        assertEq(pcg.owner(), address(pcgEngine));
        assertEq(pcg.getNumberOfMintableCards(), NUMBER_OF_MINTABLE_CARDS);
        assertEq(pcg.getExpansion(), pcgCounter - 1);
    }

    function test_PCGFactory_deployPCGExpansion_event_PCGExpanionDeployed_isEmited() external {
        address invalidAddress = makeAddr("invalid"); // This is a fake for the contract
        vm.recordLogs();
        vm.expectEmit(true, true, false, false);
        // @dev we are using invalidAddress cause we cannot get the contract's address before the deployment
        // So we do it with logs
        emit PCGExpanionDeployed(URI, EXPANSION, invalidAddress);

        vm.prank(msg.sender);
        pcgFactory.deployPCGExpansion(URI, NUMBER_OF_MINTABLE_CARDS);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 newPcgAddressBytes = entries[2].topics[3];
        assert(address(uint160(uint256(newPcgAddressBytes))) != address(0));
    }

    function test_PCGFactory_deployPCGExpansion_multipleExpansionsCanBeDeployedCorrectly() external {
        address invalidAddress = makeAddr("invalid"); // This is a fake for the contract
        for (uint256 i = 0; i < 10; i++) {
            vm.expectEmit(true, true, false, false);
            // @dev we are using invalidAddress cause we cannot get the contract's address before the deployment
            // Or rather we choose not to
            emit PCGExpanionDeployed(URI, i, invalidAddress);
            vm.prank(msg.sender);
            pcgFactory.deployPCGExpansion(URI, NUMBER_OF_MINTABLE_CARDS);
            assertEq(pcgFactory.getPcgCounter() - 1, i);
            assert(pcgFactory.getPcg(i) != address(0));
            assertEq(keccak256(abi.encodePacked(PCG(pcgFactory.getPcg(i)).uri(0))), keccak256(abi.encodePacked(URI)));
            assertEq(PCG(pcgFactory.getPcg(i)).owner(), address(pcgEngine));
            assertEq(PCG(pcgFactory.getPcg(i)).getNumberOfMintableCards(), NUMBER_OF_MINTABLE_CARDS);
            assertEq(PCG(pcgFactory.getPcg(i)).getExpansion(), i);
        }
    }
}
