//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PCG} from "../../src/PCG.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";

contract PCGTest is Test {
    PCG pcg;
    string public URI = "http://test/id:{id}";
    uint256 public EXPANSION = 0;
    uint256 public NUMBER_OF_MINTABLE_CARDS = 10;
    uint256 public FIRST_TOKEN_ID = 0;
    uint256 public STANDARD_AMOUNT = 1;

    address public INVALID_OWNER = address(0);
    uint256 public INVALID_NUMBER_OF_MINTABLE_CARDS = 0;

    address public RANDOM = makeAddr("random");
    uint256 public RANDOM_STARTING_BALANCE = 10 ether;

    function setUp() external {
        pcg = new PCG(URI, msg.sender, EXPANSION, NUMBER_OF_MINTABLE_CARDS);

        vm.deal(RANDOM, RANDOM_STARTING_BALANCE);
    }

    function test_PCG_constructor_invalidOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, INVALID_OWNER));
        new PCG(URI, INVALID_OWNER, EXPANSION, NUMBER_OF_MINTABLE_CARDS);
    }

    function test_PCG_constructor_invalidNumberOfMintableCards() external {
        vm.expectRevert(
            abi.encodeWithSelector(PCG.PCG__InvalidNumberOfMintableCards.selector, INVALID_NUMBER_OF_MINTABLE_CARDS)
        );
        new PCG(URI, msg.sender, EXPANSION, INVALID_NUMBER_OF_MINTABLE_CARDS);
    }

    function test_PCG_constructor_secondTest() external {
        PCG newPcg = new PCG(URI, msg.sender, EXPANSION, NUMBER_OF_MINTABLE_CARDS);
        assertEq(keccak256(abi.encodePacked(newPcg.uri(FIRST_TOKEN_ID))), keccak256(abi.encodePacked(URI)));
        assertEq(newPcg.owner(), msg.sender);
        assertEq(newPcg.getNumberOfMintableCards(), NUMBER_OF_MINTABLE_CARDS);
        assertEq(newPcg.getExpansion(), EXPANSION);
    }

    function test_PCG_constructor_setsVariablesCorrectly() external view {
        assertEq(keccak256(abi.encodePacked(pcg.uri(FIRST_TOKEN_ID))), keccak256(abi.encodePacked(URI)));
        assertEq(pcg.owner(), msg.sender);
        assertEq(pcg.getNumberOfMintableCards(), NUMBER_OF_MINTABLE_CARDS);
        assertEq(pcg.getExpansion(), EXPANSION);
    }

    function test_PCG_mintSingleCard_cannotBeUsedByRandom() external {
        vm.prank(RANDOM);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, RANDOM));
        pcg.mintSingleCard(RANDOM, FIRST_TOKEN_ID, STANDARD_AMOUNT);
    }

    function test_PCG_mintSingleCard_invalidCardId() external {
        uint256 invalidCardId = NUMBER_OF_MINTABLE_CARDS;
        vm.prank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(PCG.PCG__InvalidMintableCardId.selector, invalidCardId));
        pcg.mintSingleCard(RANDOM, invalidCardId, NUMBER_OF_MINTABLE_CARDS);
    }

    function test_PCG_mintSingleCard_tokenIsMintedCorrectly() external {
        vm.prank(msg.sender);
        pcg.mintSingleCard(RANDOM, FIRST_TOKEN_ID, STANDARD_AMOUNT);
        assertEq(pcg.balanceOf(RANDOM, FIRST_TOKEN_ID), STANDARD_AMOUNT);
    }

    function test_PCG_mintMultipleCards_cannotBeUsedByRandom() external {
        (uint256[] memory tokenIdsToBeMinted, uint256[] memory amountsToBeMinted) =
            _prepareArraysForMinting(false, 0, 1, 1, 1);
        vm.prank(RANDOM);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, RANDOM));
        pcg.mintMultipleCards(RANDOM, tokenIdsToBeMinted, amountsToBeMinted);
    }

    function test_PCG_mintMultipleCards_invalidCardIds() external {
        uint256 invalidCardId = NUMBER_OF_MINTABLE_CARDS;
        (uint256[] memory tokenIdsToBeMinted, uint256[] memory amountsToBeMinted) =
            _prepareArraysForMinting(true, 3, 3, 4, 15);
        vm.prank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(PCG.PCG__InvalidMintableCardId.selector, invalidCardId));
        pcg.mintMultipleCards(RANDOM, tokenIdsToBeMinted, amountsToBeMinted);
    }

    function test_PCG_mintMultipleCards_tokensAreMintedCorrectly() external {
        uint256 invalidIdPosition = 0;
        uint256 pseudoRandomInput = 4;
        uint256 length = 5;
        uint256 amounts = 13;
        (uint256[] memory tokenIdsToBeMinted, uint256[] memory amountsToBeMinted) =
            _prepareArraysForMinting(false, invalidIdPosition, pseudoRandomInput, length, amounts);
        vm.prank(msg.sender);
        pcg.mintMultipleCards(RANDOM, tokenIdsToBeMinted, amountsToBeMinted);
        if (length != 0) {
            for (uint256 i = 0; i < tokenIdsToBeMinted.length; i++) {
                uint256 tokenIdToBeChecked = tokenIdsToBeMinted[i];
                uint256 amountToBeChecked = 0;
                for (uint256 j = 0; j < tokenIdsToBeMinted.length; j++) {
                    if (tokenIdToBeChecked == tokenIdsToBeMinted[j]) {
                        amountToBeChecked += amountsToBeMinted[j];
                    }
                }
                assertEq(pcg.balanceOf(RANDOM, tokenIdsToBeMinted[i]), amountToBeChecked);
            }
        }
    }

    function _prepareArraysForMinting(
        bool _hasInvalidId,
        uint256 _invalidIdPosition,
        uint256 _pseudoRandomInput,
        uint256 _length,
        uint256 _amounts
    ) internal view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory tokenIdsToBeMinted = new uint256[](_length);
        uint256[] memory amountsToBeMinted = new uint256[](_length);
        if (_length == 0) {
            return (tokenIdsToBeMinted, amountsToBeMinted);
        }
        require(_invalidIdPosition < _length, "the position of the invalid id should be less than the length");
        for (uint256 i = 0; i < _length; i++) {
            uint256 rawTokenId = uint256(keccak256(abi.encode(_pseudoRandomInput, i)));
            uint256 tokenId = rawTokenId % NUMBER_OF_MINTABLE_CARDS;
            if (_hasInvalidId) {
                if (_invalidIdPosition == i) {
                    tokenId = NUMBER_OF_MINTABLE_CARDS;
                }
            }
            tokenIdsToBeMinted[i] = tokenId;
            amountsToBeMinted[i] = _amounts + i;
        }
        return (tokenIdsToBeMinted, amountsToBeMinted);
    }
}
