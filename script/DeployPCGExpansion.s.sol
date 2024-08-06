// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {PCGFactory} from "../src/PCGFactory.sol";

import {PCG} from "../src/PCG.sol";

contract DeployPCGExpansion is Script {
    error DeployPCGExpansion__InvalidNumberOfMintableCards(uint256 _numberOfMintableCards);
    error DeployPCGExpansion__CIDIsEmpty();
    error DeployPCGExpansion__URIAlreadyUsed(string _uri);

    function run(address pcgFactoryAddress, string memory _cid, uint256 _numberOfMintableCards) external {
        PCGFactory pcgFactory = PCGFactory(pcgFactoryAddress);
        console.log("Checking if address provided is a PCG Factory...");
        try pcgFactory.owner() returns (address pcgFactoryOwner) {
            console.log("Checking Number of Mintable Cards...");
            console.log("Number of Mintable Cards: ", _numberOfMintableCards);
            if (_numberOfMintableCards <= 0) {
                console.log("Number of Mintable cards cannot be zero. Broacast will not start...");
                revert DeployPCGExpansion__InvalidNumberOfMintableCards(_numberOfMintableCards);
            }
            console.log("Checking CID...");
            console.log("CID: ", _cid);
            if (keccak256(abi.encodePacked(_cid)) == keccak256(abi.encodePacked(""))) {
                console.log("CID cannot be empty. Broadcast will not start...");
                revert DeployPCGExpansion__CIDIsEmpty();
            }
            console.log("Checking URI...");
            string memory uri = string.concat("ipfs://", _cid, "/{id}.json");
            console.log("URI: ", uri);
            uint256 currentPcgCounter = pcgFactory.getPcgCounter();
            if (currentPcgCounter > 0) {
                for (uint256 i = 0; i < currentPcgCounter; i++) {
                    address pcgAddress = pcgFactory.getPcg(i);
                    string memory pcgUri = PCG(pcgAddress).uri(0);
                    if (keccak256(abi.encodePacked(pcgUri)) == keccak256(abi.encodePacked(uri))) {
                        console.log("New URI is the same as an old one. Broadcast will not start...");
                        revert DeployPCGExpansion__URIAlreadyUsed(uri);
                    }
                }
            }
            console.log("Starting broadcast to deploy a new pcg expansion");
            vm.startBroadcast(pcgFactoryOwner);
            pcgFactory.deployPCGExpansion(uri, _numberOfMintableCards);
            vm.stopBroadcast();
            console.log("New PCG Expansion deployed");
            uint256 newPcgCounter = pcgFactory.getPcgCounter();
            address newPcgAddress = pcgFactory.getPcg(newPcgCounter - 1);
            console.log("PCG Expansion Address: ", newPcgAddress);
        } catch {
            console.log("Address provided is not a PCGFactory. Broadcast will not start...");
        }
    }
}
