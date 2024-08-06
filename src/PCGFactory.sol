//SPDX-License-Identifier: MIT

//VERSION
pragma solidity 0.8.20;

// IMPORTS
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {PCG} from "./PCG.sol";
import {PCGEngine} from "./PCGEngine.sol";

// INTERFACES
// LIBRARIES
// CONTRACTS

// INTERFACES
// LIBRARIES
// CONTRACTS

/**
 * @title Printable Card Game Factory (PCGFactory)
 * @author John Christidis
 * @notice This is a Factory contract for deploying expansions of a printable card game (PCG)
 * @dev This contract when deployed a PCGEngine contract is also deployed at the same time
 * @dev This contract's primary use is to ceate and store PCG expansions
 * @dev This contract inherits 'Ownable' from openzeppelin and its owner is the deployer
 */
contract PCGFactory is Ownable {
    // --ERRORS--
    // --TYPE DECLARATIONS--

    // --STATE VARIABLES--
    /**
     * @dev 's_pcgs' is a mapping keeping the addresses of all PCG contracts that are deployed by PCGFactory
     * @dev The '_pcgId' is also the expansion of each PCG contract
     */
    mapping(uint256 _pcgId => address _pcgAddress) private s_pcgs;
    /**
     * @dev 's_pcgCounter' is a counter that start at 0 and everytime it a new PCG expansion is deployed it increases by one
     * @dev It also acts as a way to loop for the PCG contracts outside of the PCGFactory
     */
    uint256 private s_pcgCounter;
    /**
     * @dev 'i_pcgEngineAddress' is the address of PCGEngine contract
     * @dev It is the owner of the PCG expansions
     */
    address private immutable i_pcgEngineAddress;

    // --EVENTS--
    /**
     * @dev 'PCGExpanionDeployed' is emited when a new PCG expansion is deployed
     * @dev It holds the new URI the id of the expansion and the address of the PCG expansion
     */
    event PCGExpanionDeployed(string indexed _uri, uint256 indexed _pcgId, address indexed _pcgAddress);

    // --MODIFIERS--
    // --FUNCTIONS--
    // ----CONSTRUCTOR----
    /**
     * @dev When this contract is deployed the PCGEngine is also deployed at the same time.
     * @dev The parameters of this function are all passed in the PCGEngine.
     * @dev This contracts owner is the one who deploys it
     * @param _vrfWrapperAddress This is passed to the PCGEngine when deployed
     * It is the wrapper address used for the VRF of chainlink
     * @param _callbackGasLimit This is passed to the PCGEngine when deployed
     * It is the maximum gas that can be used for the vrf to return random results
     * It is tested that 200000 works correctly
     * @param _nativeToUsdPriceFeedAddress This is passed to the PCGEngine when deployed
     * It is chainlink's price feed address to recieve the native token's price in usd
     * It will be different for every network
     * @param _eurToUsdPriceFeedAddress This is passed to the PCGEngine when deployed
     * It is chainlink's price feed address to recieve the price of usd in eur
     * @dev Code Expalnation:
     * @dev Both '_nativeToUsdPriceFeedAddress' and '_eurToUsdPriceFeedAddress' will be used
     * to get the native token price in euro and the opposite since there is no direct price feed to do it.
     * @dev Set 'msg.sender' as the owner of the contract
     * @dev Set the counter of the PCGs to 0
     * @dev Deploys a new PCGEngine with above parameters + this contract's address
     * @dev This contract's will be used for the control of expansions when buying a PCG card
     * @dev Stores the adress of the PCGEngine to use it for the deployment of expansions
     */
    constructor(
        address _vrfWrapperAddress,
        uint32 _callbackGasLimit,
        address _nativeToUsdPriceFeedAddress,
        address _eurToUsdPriceFeedAddress
    ) Ownable(msg.sender) {
        s_pcgCounter = 0;
        PCGEngine _pcgEngine = new PCGEngine(
            _vrfWrapperAddress,
            _callbackGasLimit,
            _nativeToUsdPriceFeedAddress,
            _eurToUsdPriceFeedAddress,
            address(this)
        );
        i_pcgEngineAddress = address(_pcgEngine);
    }

    // ----EXTERNAL----
    /**
     * @dev 'deployPCGExpansion' deploys new expansions of the PCG contract
     * @dev It can only be used by the owner of the contract which is the one who deployed the contract
     * @param _uri The uri of the tokens that is pointing to an ipfs folder
     * (Careful because there are no checks to see if the uri is valid! WEAK POINT! Cannot be changed later)
     * @param _numberOfMintableCards The number of mintable cards of this expansion
     * (This number is also a WEAK POINT since there are no check to ensure that this number is correct
     * e.g. I want 10 cards to be mintable but accidentily I add 9 or 11! Cannot be changed later)
     * When the PCG contract is deployed it is checked if this number is above 0 else it reverts
     * @dev Sets a uint for the new PCG expansion equal to the PCG counter
     * @dev Deploys the new PCG contract with:
     * 1) the new uri of the cards
     * 2) the address of the PCGEngine that was deployed in the constructor which is passed as the owner of the new PCG contract
     * 3) the id of the new PCG expansion
     * 4) the number of mintable cards which in the deployement is checked if it is above 0 else it reverts
     * @dev Code Expalnation:
     * @dev Saves the address of the PCG contract to the mapping of PCG contracts with key the expansion number
     * @dev Increases the counter by 1
     * @dev Emits the event signifying the new PCG Contract
     */
    function deployPCGExpansion(string memory _uri, uint256 _numberOfMintableCards) external onlyOwner {
        uint256 newPcgId = s_pcgCounter;
        PCG pcg = new PCG(_uri, i_pcgEngineAddress, newPcgId, _numberOfMintableCards);
        s_pcgs[newPcgId] = address(pcg);
        s_pcgCounter++;
        emit PCGExpanionDeployed(_uri, newPcgId, address(pcg));
    }

    // ----PUBLIC----
    // ----INTERNAL----

    // ----PRIVATE----
    // ----EXTERNAL--PUBLIC--VIEW----
    /**
     * @dev 'getPcg' returns the address of the PCG expansion contract that '_pcgId' signifies
     * @param _pcgId is the id or expansion of the PCG expansion contract
     * @dev Searches the 's_pcgs' mapping to find the address of the PCG with that id or expansion and returns it
     * @dev This function is also used in the PCGEngine, when a player purchases a card
     * It is used to find the address of the PCG contract because they use the id of the expansion
     * That way it is also checked if the PCG contract is valid
     * Also it adds as layer of protection as it can only be used by PCG contracts created by PCGFactory
     */
    function getPcg(uint256 _pcgId) external view returns (address) {
        return (s_pcgs[_pcgId]);
    }

    /**
     * @dev 'getPcgCounter' returns the value of 's_pcgCounter'
     */
    function getPcgCounter() external view returns (uint256) {
        return (s_pcgCounter);
    }

    /**
     * @dev 'getPcgEngine' returns the address of PCGEngine
     */
    function getPcgEngine() external view returns (address) {
        return i_pcgEngineAddress;
    }

    // ----INTERNAL--PRIVATE--VIEW----
    // ----EXTERNAL--PUBLIC--PURE----
    // ----INTERNAL--PRIVATE--PURE----
}
