//SPDX-License-Identifier: MIT

//VERSION
pragma solidity 0.8.20;

contract FakePCGFactoryOwnerMock {
    fallback() external payable {
        revert();
    }
}
