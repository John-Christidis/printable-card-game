//SPDX-License-Identifier: MIT

//VERSION
pragma solidity 0.8.20;

import {PCGEngine} from "../../src/PCGEngine.sol";
import {MockLinkToken} from "@chainlink/contracts/src/v0.8/mocks/MockLinkToken.sol";

contract MaliciousPCGFactoryOwnerVRFWrapperMock {
    PCGEngine pcgEngine;
    MockLinkToken mockLinkToken;

    constructor() {
        mockLinkToken = new MockLinkToken();
    }

    function setPcgEngine(address _pcgEngineAddress) external {
        pcgEngine = PCGEngine(_pcgEngineAddress);
    }

    function link() external view returns (address) {
        return address(mockLinkToken);
    }

    fallback() external payable {
        if (address(pcgEngine).balance > 0) {
            pcgEngine.withdraw();
        }
    }

    receive() external payable {
        if (address(pcgEngine).balance > 0) {
            pcgEngine.withdraw();
        }
    }
}
