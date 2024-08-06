//SPDX-License-Identifier: MIT

//VERSION
pragma solidity 0.8.20;

// IMPORTS
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";

// INTERFACES

// LIBRARIES

// CONTRACTS

/**
 * @title Printable Card Game (PCG)
 * @author John Christidis
 * @notice This is an ERC1155 contract with tokens used to represent printable cards
 * @dev This contract will be deployed by PCGFactory contract everytime a new expansion will be added to the game
 * @dev This contract will be governed by PCGEngine
 * @dev Cards will be distributed to players by the PCGEngine randomly
 * @dev The contract inherits the basic ERC1155 contract as well as the Ownable contract.
 * @dev The owner will be the PCGEngine contract and this is managed in the time of this contract's deployment
 * from PCGFactory.
 */
contract PCG is ERC1155, Ownable {
    // --ERRORS--

    error PCG__InvalidMintableCardId(uint256 _mintableCardId);
    error PCG__InvalidNumberOfMintableCards(uint256 _numberOfMintableCards);
    // --TYPE DECLARATIONS--

    // --STATE VARIABLES--
    /**
     * @dev 'i_expansion' is the expansion of the PCG contract.
     * @dev It is set in the constructor and it is used in the PCGFactory for finding if the PCG Expansion is valid
     */
    uint256 private immutable i_expansion;
    /**
     * @dev 'i_numberOfMintableCards' is the number of mintable cards of this expansion.
     * @dev It is set in the constructor and cannot be changed once set.
     * @dev It cannot be 0 because there will be 0 mintable cards which make the contract invalid
     * @dev The ids of the contact will be from 0 up to this number - 1
     * @dev e.g. if 'i_numberOfMintableCards' = 5 the ids of mintable cards will be 0,1,2,3,4
     * @dev It is used to find card randomly that will be minted and given to the playrs from this expansion
     */
    uint256 private immutable i_numberOfMintableCards;

    // --EVENTS--

    // --MODIFIERS--

    // --FUNCTIONS--

    // ----CONSTRUCTOR----
    /**
     * @dev When the contract is deployed it set the URI of the tokens and the owner which is gonna be PCGEngine
     * @dev The contract is deployed by PCGFactory
     * @param _uri The uri of the tokens that is pointing to an ipfs folder
     * @param _owner The address of PCGEngine which is gonna be the owner of the contract
     * @param _expansion The number of the expansion
     * @param _numberOfMintableCards The number of mintable cards in total. This cannot be 0.
     * @dev Set URI and owner
     * @dev Check if '_numberOfMintableCards' < 0
     * @dev Set the expansion number
     * @dev Set the number of mintable cards
     */
    constructor(string memory _uri, address _owner, uint256 _expansion, uint256 _numberOfMintableCards)
        ERC1155(_uri)
        Ownable(_owner)
    {
        if (_numberOfMintableCards <= 0) {
            revert PCG__InvalidNumberOfMintableCards(_numberOfMintableCards);
        }
        i_expansion = _expansion;
        i_numberOfMintableCards = _numberOfMintableCards;
    }

    // ----EXTERNAL----
    /**
     * @dev 'mintSingleCard' is a function only used by PCGEngine to mint a single card after a player purchase a random card.
     * @dev As it is setup the PCGEngine will only mint one copy and transfer it to the purchaser
     * @dev The card will be random and the function will be called by chainlink vrf
     * @param _reciever is the purchaser which will recieve the card after the mint
     * @param _mintableCardId is the id of the card going to be minted.
     * The id will be from 0 up to 'i_numberOfMintableCards' - 1
     * e.g. if 'i_numberOfMintableCards' = 5 the id will be 0 <= id <= 4
     * @param _amount this will always be 1 as the PCGEngine is structured
     * It is the amount of the cards id that will be minted
     * @dev Code Expalnation:
     * @dev Check if the id is less than number of mintable cards else it reverts
     * @dev Mint the amount = 1 copies of card of the id to the purcaser
     */
    function mintSingleCard(address _reciever, uint256 _mintableCardId, uint256 _amount) external onlyOwner {
        if (_mintableCardId >= i_numberOfMintableCards) {
            revert PCG__InvalidMintableCardId(_mintableCardId);
        }
        _mint(_reciever, _mintableCardId, _amount, "");
    }

    /**
     * @dev 'mintMultipleCards' is a function only used by PCGEngine to mint multiple cards after a player purchase a random card.
     * @dev As it is setup the PCGEngine will only mint one copy of each card and transfer it to the purchaser
     * @dev However it is possible to mint twice or three times copies of a card with the same id
     * @dev e.g. '_mintableCardIds' = [3,3,3] '_amounts' = [1, 1, 1]
     * @dev The cards will be random and the function will be called by chainlink vrf
     * @dev The maximum number of cards minted can be up to 3 and this arrives from the PCGEngine
     * @dev This limit can change only in the code it can be up to 10 due to chainlinks vrf limitation
     * @dev Once the PCGEngine is deployed it cannot change
     * @param _reciever is the purchaser which will recieve the cards after the mint
     * @param _mintableCardIds is an array of the ids of the cards going to be minted.
     * The ids will be from 0 up to 'i_numberOfMintableCards' - 1
     * e.g. if 'i_numberOfMintableCards' = 5 the ids will be 0 <= id <= 4
     * As mentioned ids in '_mintableCardIds' can be the same e.g. [1,2,2]
     * @param _amounts this array will always:
     * have values of 1 as the PCGEngine is structured
     * have the same length as the '_mintableCardIds' arrays length which is checked in PCGEngine
     * It is the amounts of each card that will be minted
     * @dev Code Expalnation:
     * @dev For each id in the arrays of ids
     * @dev Check if the id is less than number of mintable cards else it reverts
     * @dev Mint each amount = 1 copies of card of the id to the purcaser
     * @dev The function used is 'mintBatch' from ERC1155
     */
    function mintMultipleCards(address _reciever, uint256[] memory _mintableCardIds, uint256[] memory _amounts)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _mintableCardIds.length; i++) {
            if (_mintableCardIds[i] >= i_numberOfMintableCards) {
                revert PCG__InvalidMintableCardId(_mintableCardIds[i]);
            }
        }
        _mintBatch(_reciever, _mintableCardIds, _amounts, "");
    }

    // ----PUBLIC----

    // ----INTERNAL----

    // ----PRIVATE----

    // ----EXTERNAL--PUBLIC--VIEW----
    /**
     * @dev 'getNumberOfMintableCards' returns the number of mintable cards for this expansion
     * @dev this function is used in the PCGEngine to find the cards to be minted randomly
     */
    function getNumberOfMintableCards() external view returns (uint256) {
        return i_numberOfMintableCards;
    }

    /**
     * @dev 'getExpansion' returns the expansion number of this contract
     */
    function getExpansion() external view returns (uint256) {
        return i_expansion;
    }

    // ----INTERNAL--PRIVATE--PURE----
}
