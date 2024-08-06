//SPDX-License-Identifier: MIT

//VERSION
pragma solidity 0.8.20;

// IMPORTS
import {PCG} from "./PCG.sol";
import {PCGFactory} from "./PCGFactory.sol";
import {PriceConverter} from "./libraries/PriceConverter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VRFV2PlusWrapperConsumerBase} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
// INTERFACES
// LIBRARIES
// CONTRACTS
/**
 * @title Printable Card Game Engine (PCGEngine)
 * @author John Christidis
 * @notice This is the engine contract that governs printable card game expansions (PCG).
 * PCG expansions are ERC1155 token contracts that represent cards
 * From this contracts users are able to purchase cards randomly
 * @dev For the randomness this contract uses chainlink VRF version 2.5
 * @dev Specifically it uses a direct funding approach which means as it inherits 'VRFV2PlusWrapperConsumerBase'
 * that the payment of the oracle happens at the time of the request
 * @dev The oracle is paid in native currency so for e.g. if it is for Ethereum it is paid in Ether
 * @dev This contract will be deployed by PCGFactory contract by the same time the PCGFactory is deployed
 * @dev The owner of this contract will be PCGFactory. The owner is also inherited by the 'VRFV2PlusWrapperConsumerBase'
 * @dev This contract has a single function that users will use to make a transaction to the blockchain.
 * This function is used to purchase cards so to avoid attacks this contract also inherits the 'ReentrancyGuard' of Openzeppelin
 * @dev The workflow of this contract is simple:
 * 1) Users call the function 'purchasePCGCards' to purchase 1-3 cards (The payment is explained later)
 * 2) The VRF contract is triggered to later send random numbers that will be used for choosing the cards to mint
 * 3) The purchase is stored on a mapping
 * 4) The VRF chainlink nodes triggers the function 'fulfillRandomWords' as a callback. (This function can only be called by the chainlink VRF contracts)
 * 5) The random numbers are proccessed to find the cards to be minted and then they are minted to the user that made the purchase
 * @dev The payment is split in 2 components
 * 1) The card price
 *      a) The card price is a constant and is in euros per card
 *      b) It is calculated by using chainlinks pricefeeds in the library 'PriceConverter'
 *      c) Two pricefeeds are used, one for Euro to USD and one for USD to the native currency e.g. ether in ethereum
 * 2) The vrf cost to get the randomness which is paid directly to chainlink
 *      a) It is calculated in the native currency
 *      b) This price is not constant and it depends on multiple factors
 *          i) The current gas price
 *          ii) The number of cards to be purchased
 *          iii) The different blockchain network
 *          iv) The callback gas limitations added when the contract was first deployed (this is constant in the contract)
 * The sum of these two is the least the users must pay to successfuly purchase the cards
 * @dev This contract keeps the funds of the payments (ONLY from the card prices)
 * @dev The owner of the PCGFactory may choose to withdraw them
 * @dev To sum up this contract manages random card distribution by minted cards to users that purchase them
 */

contract PCGEngine is VRFV2PlusWrapperConsumerBase, ReentrancyGuard {
    // --ERRORS--
    error PCGEngine__NotEnoughNativeToPurchaseCards(uint32 _numberOfCardsToPurchase);
    error PCGEngine__NotEnoughNativeToPayForVrf(uint32 _numberOfCards, uint256 _vrfPrice);
    error PCGEngine__CardsToPurchaseMoreThanLimit(uint32 _numberOfCardsToPurchase);
    error PCGEngine__CardsToPurchaseCannotBeZeroOrLess(uint32 _numberOfCardsToPurchase);
    error PCGEngine__PurchaseIsAlreadyCompleted(uint256 _purchaseId);
    error PCGEngine__RandomCardsAreNotEqualToPurchasedCards(uint256 _randomCardsToMint);
    error PCGEngine__InvalidPCGExpansion(uint256 _pcgId);
    error PCGEngine__OnlyPCGFactoryOwnerCanWithdrawEther(address _notWithdrawer);
    error PCGEngine__WithdrawFailed();

    // --TYPE DECLARATIONS--
    /**
     * @dev PriceConverter is a library that manages the conversions between euros and native currency
     * @dev It can be used on uint256 but its main focus is to change the card price of the payment to euro and the opposite
     * @dev It achieves it by using chainlinks pricefeeds and specifically the EUR to USD and Native Currency to USD e.g. EUR to USD
     * @dev It is used on two functions:
     * 1) 'purchasePcgCards' to calculate the card price the user has to pay from native currency to euro
     * 2) 'estimatePcgCardsPrice' to estimate the card price the user has to pay in native currency
     */
    using PriceConverter for uint256;

    /**
     * @dev Purchase is a struct that is used to keep track of the purcases
     * @dev This is important cause vrf is used in two transactions so it needs to keep track of them
     * @dev 'consumer' is the address of the user that made the purchase
     * @dev 'pcgAddress' is address of the PCG expansion that the user made the purchase from.
     * @dev 'pending' is the state of the purchase if it fulfilled or not
     */
    struct Purchase {
        address consumer;
        address pcgAddress;
        bool pending;
    }
    // --STATE VARIABLES--
    /**
     * @dev 'i_vrfWrapperAddress' is the address of the VRF wrapper that handles the vrf functionality
     */

    address private immutable i_vrfWrapperAddress;
    /**
     * @dev 'i_callbackGasLimit' is the maximum amount of gas to be spend for the callback of fulfillRandomWord by chainlink
     * @dev if this limit is surpassed the function reverts
     * @dev The bigger this number the bigger the payment so it needs to be adjusted correctly
     * @dev 200000 seems to work correctly
     */
    uint32 private immutable i_callbackGasLimit;
    /**
     * @dev 'REQUEST_CONFIRMATIONS' is a needed param for vrf it signifies how much confirmation should the chainlink node wait
     * before responding. The longer the more secure but also slower
     * @dev min = 3, max = 20
     */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;

    /**
     * @dev 'i_nativeToUsdPriceFeedAddress' is the address of chainlink's price feed contract
     * It is used to get the price of the native currency to USD
     */
    address private immutable i_nativeToUsdPriceFeedAddress;
    /**
     * @dev 'i_eurToUsdPriceFeedAddress' is the address of chainlink's price feed contract
     * It is used to get the price of euro to USD
     */
    address private immutable i_eurToUsdPriceFeedAddress;

    /**
     * @dev 's_lastPriceConversion' is used to store the last conversion from native currency to euro
     * This is important because price feeds can return results that cannot be used in the contract like 0 or negative numbers
     * Instead of breaking the functionality we use the last price conversion to calculate the price of cards.
     */
    uint256 private s_lastPriceConversion;

    /**
     * @dev 'i_pcgFactoryAddress' is the address of the PCGFactory which is also the owner of the contract
     * It is used to find if an id of an input from a user is valid by checking PCGFactory's mapping of PCG addresses
     */
    address private immutable i_pcgFactoryAddress;

    /**
     * @dev 's_purchases' is a mapping that maps the id that is returned from the 'requestRandomnessPayInNative'
     * function to a Purchase.
     * This helps the to find the consumer when calling callback fulfillRandomWords is used
     * Check from what address of PCG the user made the purchase
     * It also stores the state of the purchase, if it has been fulfilled or not
     */
    mapping(uint256 _purchaseId => Purchase _purchase) private s_purchases;

    /**
     * @dev 'CARD_PRICE_EUR' is a constant number that signifies the price of a single card in euro currency
     */
    uint256 private constant CARD_PRICE_EUR = 2 * 10 ** 18;
    /**
     * @dev 'MAX_CARD_PURCHASE_LIMIT' is a constant that state what is the maximum number of cards that can be purchased at once
     * This can be up to 10 due to vrf's limitations
     */
    uint32 private constant MAX_CARD_PURCHASE_LIMIT = 3;
    /**
     * @dev 'MIN_CARD_PURCHASE_LIMIT' is a constant that state what is the minimum number of cards that can be purchased at once
     */
    uint32 private constant MIN_CARD_PURCHASE_LIMIT = 1;

    // --EVENTS--
    /**
     * @dev 'PCGCardsPurchased' is emited when a purchase is triggered.
     * This event triggers before the successful transfer of the cards
     */
    event PCGCardsPurchased(uint256 indexed _purchaseId, address indexed _consumer, uint256 indexed _pcgId);
    /**
     * @dev 'PCGCardsPurchaseFullfilled' is emit from 'fulfillRandomness' function when the cards
     * have been successfuly minted to the consumer
     */
    event PCGCardsPurchaseFullfilled(
        uint256 indexed _purchaseId, address indexed _consumer, address indexed _pcgAddress
    );
    // --MODIFIERS--
    // --FUNCTIONS--
    // ----CONSTRUCTOR----
    /**
     * @dev This contract is deployed in the constructor of the PCGFactory
     * This means tha both contracts are deployed on the same time
     * @param _vrfWrapperAddress is address of the wrapper that manages the vrf requests
     * @param _callbackGasLimit It is the maximum gas that can be used for the vrf to return random results
     * It is tested that 200000 works correctly
     * @param _nativeToUsdPriceFeedAddress It is chainlink's price feed address to recieve the native token's price in usd
     * It will be different for every network
     * @param _eurToUsdPriceFeedAddress This is passed to the PCGEngine when deployed
     * It is chainlink's price feed address to recieve the price of usd in eur
     * @dev Both '_nativeToUsdPriceFeedAddress' and '_eurToUsdPriceFeedAddress' will be used
     * to get the native token price in euro and the opposite since there is no direct price feed to do it.
     * @param _pcgFactoryAddress is the address of the pcgFactory and is passed to validate the existance
     * of PCG expansion contracts during the purchase
     * @dev Code Expalnation:
     * @dev sets the '_vrfWrapper' as VRFV2PlusWrapperConsumerBase
     * @dev sets all parameters to their appropriate variables
     * @dev uses the lib PriceConverter to calculate the price of the current price native to euro
     * @dev sets that price as the last price conversion in case of bad pricefeeds
     */

    constructor(
        address _vrfWrapperAddress,
        uint32 _callbackGasLimit,
        address _nativeToUsdPriceFeedAddress,
        address _eurToUsdPriceFeedAddress,
        address _pcgFactoryAddress
    ) VRFV2PlusWrapperConsumerBase(_vrfWrapperAddress) {
        i_vrfWrapperAddress = _vrfWrapperAddress;
        i_callbackGasLimit = _callbackGasLimit;
        i_nativeToUsdPriceFeedAddress = _nativeToUsdPriceFeedAddress;
        i_eurToUsdPriceFeedAddress = _eurToUsdPriceFeedAddress;
        i_pcgFactoryAddress = _pcgFactoryAddress;
        (, uint256 currentPriceConversion) = CARD_PRICE_EUR.getConversionRate(
            i_nativeToUsdPriceFeedAddress, i_eurToUsdPriceFeedAddress, s_lastPriceConversion
        );
        s_lastPriceConversion = currentPriceConversion;
    }
    // ----EXTERNAL----

    /**
     * @dev 'purchasePcgCards' is the only function that can be called from any user and makes a transaction to the blockchain
     * @dev It is a payable function that is also nonReentrant since users may try an attack to the contract from it
     * @dev This function is called in order to make a purchase of 1-3 cards from a PCG expansion
     * @dev When this function is called it also makes a request to the vrf to get random numbers that can be used
     * in the callback function 'fulfillRandomWords' to mint the cards to the consumer
     * @dev This function is step 1 of the two steps needed to purchase cards from PCGEngine.
     * @dev The step 2 is handled by the callback
     * @param _pcgId is the id of the PCG expansion that the user purchases cards from
     * The id is a parameter so it needs to be checked before continueing for the rest of the function
     * @param _numberOfCards is the number of cards the consumer requests to purchase
     * and can be from 1 to 'CARD_PURCHASE_LIMIT' = 3 else the function reverts
     * @dev This function is payable and the payment can be estimated from the function 'estimatePcgCardsPrice'
     * @dev The payment is split in 2 components
     * 1) The card price
     *     a) The card price is a constant and is in euros per card
     *     b) It is calculated by using chainlinks pricefeeds in the library 'PriceConverter'
     *     c) Two pricefeeds are used, one for Euro to USD and one for USD to the native currency e.g. ether in ethereum
     * 2) The vrf cost to get the randomness which is paid directly to chainlink
     *     a) It is calculated in the native currency
     *     b) This price is not constant and it depends on multiple factors
     *         i) The current gas price
     *         ii) The number of cards to be purchased
     *         iii) The different blockchain network
     *         iv) The callback gas limitations added when the contract was first deployed (this is constant in the contract)
     * @dev Code Expalnation:
     * @dev Checks if requested number of cards is more than the lower limit else it reverts
     * @dev Checks if requested number of cards is less than the upper limit else it reverts
     * @dev Calculates the cost of vrf by using the inherited function of  'calculateRequestPriceNative' of the wrapper
     * This is also calculated in the consumer of the vrf that this contract inherits from
     * but it is calculated by the balance of the contract and not the 'msg.value' of the function
     * @dev Checks if 'msg.value' is bigger than vrf's cost else it reverts
     * @dev Calculates the card price in native by substracting the vrf cost from 'msg.value'
     * @dev Converts price to euro using the PriceConverter's functionality
     * @dev Saves the new conversion rate to be used in case of bad results in pricefeeds returns 0 or negative numbers
     * @dev Checks if card price in euro is more than 'CARD_PRICE_EUR' else it reverts
     * @dev Gets an instant of PCGFactory
     * @dev Finds the PCG expansion stored in the mapping of pcgs in PCGFactory that the cards are requested from
     * @dev Temporarily stores the address of the PCG
     * @dev Checks if it has a valid address else it reverts
     * @dev Makes the request using the inherited function 'requestRandomnessPayInNative' and immidiately pays for the costs of the vrf
     * The 'requestRandomnessPayInNative' returns an id that is then used as key in the mapping of the purchases
     * @dev Stores the new purchase with key the id mentioned above
     * This is useful because in the callback function of the vrf there is no need to make additional searches
     * @dev The purchase keeps the consumer, the address of the PCG expansion and is now pending
     * @dev Finally emit the event 'PCGCardsPurchased'
     */
    function purchasePcgCards(uint256 _pcgId, uint32 _numberOfCards) external payable nonReentrant {
        //gas cost  anvil 174281
        if (_numberOfCards < MIN_CARD_PURCHASE_LIMIT) {
            revert PCGEngine__CardsToPurchaseCannotBeZeroOrLess(_numberOfCards);
        }
        if (_numberOfCards > MAX_CARD_PURCHASE_LIMIT) {
            revert PCGEngine__CardsToPurchaseMoreThanLimit(_numberOfCards);
        }
        uint256 vrfCost = i_vrfV2PlusWrapper.calculateRequestPriceNative(i_callbackGasLimit, _numberOfCards);
        if (vrfCost > msg.value) {
            revert PCGEngine__NotEnoughNativeToPayForVrf(_numberOfCards, vrfCost);
        }
        uint256 cardsPrice = msg.value - vrfCost;
        (uint256 cardsPriceInEur, uint256 currentPriceConversion) = cardsPrice.getConversionRate(
            i_nativeToUsdPriceFeedAddress, i_eurToUsdPriceFeedAddress, s_lastPriceConversion
        );
        s_lastPriceConversion = currentPriceConversion;
        if (cardsPriceInEur < CARD_PRICE_EUR * _numberOfCards) {
            revert PCGEngine__NotEnoughNativeToPurchaseCards(_numberOfCards);
        }

        PCGFactory pcgFactory = PCGFactory(i_pcgFactoryAddress);
        address pcgAddress = pcgFactory.getPcg(_pcgId);
        if (pcgAddress == address(0)) {
            revert PCGEngine__InvalidPCGExpansion(_pcgId);
        }
        (uint256 purchaseId,) = requestRandomnessPayInNative(
            i_callbackGasLimit,
            REQUEST_CONFIRMATIONS,
            _numberOfCards,
            // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
            VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
        );

        s_purchases[purchaseId] = Purchase({consumer: msg.sender, pcgAddress: pcgAddress, pending: true});

        emit PCGCardsPurchased(purchaseId, msg.sender, _pcgId);
    }

    /**
     * @dev 'withdraw' is an external nonReentrant function that only allows the owner of the PCGFactory
     * to retrieve all the currency stored in the contract. There are 3 ways of withdrawing currency
     * from contracts and here the low level call is used as it is the most secured.
     * @dev The currency stored will be the sum from all purchases from the contract subtracting the vrf costs
     * @dev Code Explanation
     * @dev Gets an instance of PCGFactory using its address
     * @dev Gets the owner of PCGFactory
     * @dev Checks if the one calling the function is the owner of PCGFactory else it reverts
     * @dev Attempts to send the stored balance of the contract to the owner of PCGFactory by
     * using the low level call function
     * @dev A bool is returned that states if the transfer was successful
     * @dev If it was not successful it reverts
     */
    function withdraw() external nonReentrant {
        PCGFactory pcgFactory = PCGFactory(i_pcgFactoryAddress);
        address withdrawer = pcgFactory.owner();
        if (msg.sender != withdrawer) {
            revert PCGEngine__OnlyPCGFactoryOwnerCanWithdrawEther(msg.sender);
        }

        // // transfer
        // payable(msg.sender).transfer(address(this).balance);

        // // send
        // bool sendSuccess = payable(msg.sender).send(address(this).balance);
        // require(sendSuccess, "Send failed");

        // call
        (bool callSuccess,) = payable(withdrawer).call{value: address(this).balance}("");
        //require(callSuccess, "Call failed");
        if (!callSuccess) {
            revert PCGEngine__WithdrawFailed();
        }
    }

    // ----PUBLIC----

    // ----INTERNAL----
    /**
     * @dev 'fulfillRandomWords' is the function called by chainlink when random numbers are requested
     * @dev This function overrides the original function and is also internal so it can only be called by the wrapper contract
     * @dev When the random numbers are requested this function takes as parameters the returned random numbers as well as the id of the request
     * @param _purchaseId is the id of the request which we also use to store the purchase hence the name
     * This way it is easy to find purchase by using it as key for the mapping
     * @param _randomWords is an array of random uint256 numbers which are used to mint the cards
     * @dev These parameters are passed to the internal '_fulfillPcgCardsPurchase'
     */
    function fulfillRandomWords(uint256 _purchaseId, uint256[] memory _randomWords) internal override {
        _fulfillPcgCardsPurchase(_purchaseId, _randomWords);
    }
    /**
     * @dev '_fulfillPcgCardsPurchase' has the functionality to find the random cards and mint them to the consumers
     * @param _purchaseId is the id of the request which we also use to store the purchase hence the name
     * This way it is easy to find purchase by using it as key for the mapping
     * @param _randomWords is an array of random uint256 numbers which are used to mint the cards
     * @dev Code Expalnation:
     * @dev Finds the purchase from the mapping using the '_purchaseId'
     * @dev Check if the request is pending else it reverts
     * @dev From the purchase stored takes the address of the PCG expansion contract and instanciates it
     * @dev From the PCG contract finds the number of mintable cards by calling 'getNumberOfMintableCards'
     * @dev Passes the random numbers with the number of mintable cards in the '_prepareForMinting' function
     * to recieve two arrays:
     * 1) The ids of the cards thar are going to be mint e.g. [50, 4]
     * 2) The amounts which will always be a list of ones e.g. [1, 1]
     * @dev Checks if the length of arrays and if it 1 it uses the PCG's 'mintSingleCard' to mint a single card
     * else it uses 'mintMultipleCards' to mint multiple cards
     * Both of these take the same parameters, the consumers that will recieve the cards the ids and the amounts
     * @dev Marks the purchase as completed
     * @dev Emits the event 'PCGCardsPurchaseFullfilled'
     * @dev EXAMPLE: In the arrays of ids=[50,4], amounts=[1,1] (These arrays always have the same length)
     * The minted will be:
     * card id: 50, amount: 1
     * card id: 4,  amount: 1
     */

    function _fulfillPcgCardsPurchase(uint256 _purchaseId, uint256[] memory _randomWords) internal {
        Purchase storage purchase = s_purchases[_purchaseId];
        if (!purchase.pending) {
            revert PCGEngine__PurchaseIsAlreadyCompleted(_purchaseId);
        }
        PCG pcg = PCG(purchase.pcgAddress);
        uint256 _numberOfMintableCards = pcg.getNumberOfMintableCards();
        (uint256[] memory cardIdsToMint, uint256[] memory amountsToMint) =
            _prepareForMinting(_randomWords, _numberOfMintableCards);

        if (cardIdsToMint.length == 1) {
            pcg.mintSingleCard(purchase.consumer, cardIdsToMint[0], amountsToMint[0]);
        } else {
            pcg.mintMultipleCards(purchase.consumer, cardIdsToMint, amountsToMint);
        }

        purchase.pending = false;
        emit PCGCardsPurchaseFullfilled(_purchaseId, purchase.consumer, purchase.pcgAddress);
    }

    // ----PRIVATE----
    // ----EXTERNAL--PUBLIC--VIEW----

    /**
     * @dev 'estimatePcgCardsPrice' is a function that returns the price estimation of a purchase in native currency.
     * @dev This includes the price of the cards and the costs of the vrf
     * @dev The price is split in 2 components
     * 1) The card price
     *     a) The card price is a constant and is in euros per card
     *     b) It is calculated by using chainlinks pricefeeds in the library 'PriceConverter'
     *     c) Two pricefeeds are used, one for Euro to USD and one for USD to the native currency e.g. ether in ethereum
     * 2) The vrf cost to get the randomness which is paid directly to chainlink
     *     a) It is calculated in the native currency
     *     b) This price is not constant and it depends on multiple factors
     *         i) The current gas price
     *         ii) The number of cards to be purchased
     *         iii) The different blockchain network
     *         iv) The callback gas limitations added when the contract was first deployed (this is constant in the contract)
     * @param _numberOfCards is the number of cards that to be minted
     * @param _gasPrice is the current price of gas in the network in wei (or other native currency).
     * As an input it is uint96 in order to avoid breaks of calculations in the estimations but it is later used as uint256.
     * This should be monitored externaly as it changes rapidly and this is why it added as a parameter
     * It cannot be calculated automatically because this is not a transaction, it is a view function
     * '_gasPrice' significally chagnes the costs of the vrf as it can be as low as 1 up to 1000 gwei
     * This could result in costs that can 100 times more than others
     * @return _numberOfCards is returned in case of adding an invalid number so that it can be used later
     * @return vrfCosts is the costs for using chainlink vrf mentioned above in native currency
     * @return cardsPriceInNative is the price of the cards in native currency
     * @return totalPrice is the sum of the vrf costs and cards price.
     * This is what the users will be required to pay to purchase the cards
     * @dev Code Explanation:
     * @dev Checks if the number of cards is valid
     * @dev If it was less than the minimum number of cards that can be purchases it changes the number to the minimum which is 1
     * @dev If it was more than the maximum it changes the number to the maximum which is 3
     * @dev Uses estimateRequestPriceNative from vrf wrapper to calculate vrf costs in native (1)
     * @dev Calculates the price of cards in euro
     * @dev Uses PriceConverter library's functionality for uint256 to convert price of card in native (2)
     * @dev Calculates the sum of the two costs in native (3)
     * @dev Returns all three of them (1, 2, 3)
     */
    function estimatePcgCardsPrice(uint32 _numberOfCards, uint96 _gasPrice)
        external
        view
        returns (uint32, uint256, uint256, uint256)
    {
        if (_numberOfCards > MAX_CARD_PURCHASE_LIMIT) {
            _numberOfCards = MAX_CARD_PURCHASE_LIMIT;
        }
        if (_numberOfCards < MIN_CARD_PURCHASE_LIMIT) {
            _numberOfCards = MIN_CARD_PURCHASE_LIMIT;
        }
        uint256 vrfCosts =
            i_vrfV2PlusWrapper.estimateRequestPriceNative(i_callbackGasLimit, _numberOfCards, uint256(_gasPrice));
        uint256 cardsPriceInEur = _numberOfCards * CARD_PRICE_EUR;
        uint256 cardsPriceInNative = cardsPriceInEur.getReverseConversionRate(
            i_nativeToUsdPriceFeedAddress, i_eurToUsdPriceFeedAddress, s_lastPriceConversion
        );
        uint256 totalPrice = vrfCosts + cardsPriceInNative;
        return (_numberOfCards, vrfCosts, cardsPriceInNative, totalPrice);
    }
    /**
     * @dev 'getPurchase' is a view function that returns a Purchase and more specifically
     * the address of the consumer, the PCG expansion address that they made the purchase from and if it is pending
     * @param _purchaseId is the id of the purchase which is the same as the id that is returned from the vrf request
     * @dev NOTE that this contract does not keep track of the number of ids and they are not placed in sequence in the mapping
     * This means that there is no way to get all the purchases in an esay way. If this is needed,
     * the contract has to be modified to keep track of the positions of purchases or add the functionality externally
     * from an indexing protocol like the Graph.
     */

    function getPurchase(uint256 _purchaseId) external view returns (address, address, bool) {
        Purchase memory purchase = s_purchases[_purchaseId];
        return (purchase.consumer, purchase.pcgAddress, purchase.pending);
    }

    /**
     * @dev 'getVrfConfig' returns the configurations of the vrf in the contract.
     * the wrapper address, the callback Gas limit and the request confirmations
     */
    function getVrfConfig() external view returns (address, uint32, uint16) {
        return (i_vrfWrapperAddress, i_callbackGasLimit, REQUEST_CONFIRMATIONS);
    }

    /**
     * @dev 'getPriceFeedAddresses' returns the addresses of the chainlink contracts pricefeeds
     * used in the PriceConverter library of the native currency to usd and euro to usd
     */
    function getPriceFeedAddresses() external view returns (address, address) {
        return (i_nativeToUsdPriceFeedAddress, i_eurToUsdPriceFeedAddress);
    }

    /**
     * @dev 'getLastPriceConverstion' returns the last price conversion calculated from a puchase
     */
    function getLastPriceConverstion() external view returns (uint256) {
        return s_lastPriceConversion;
    }

    /**
     * @dev 'getPcgFactoryAddress' returns the address of the PCGFactory which is also the owner of this contract
     */
    function getPcgFactoryAddress() external view returns (address) {
        return i_pcgFactoryAddress;
    }

    // ----INTERNAL--PRIVATE--VIEW----
    // ----EXTERNAL--PUBLIC--PURE----

    /**
     * @dev 'getCardPrice' returns the price per card in euro
     */
    function getCardPrice() external pure returns (uint256) {
        return CARD_PRICE_EUR;
    }

    /**
     * @dev 'getMaxCardPurchaseLimit' returns the upper limit of cards that can be purchased
     */
    function getMaxCardPurchaseLimit() external pure returns (uint32) {
        return MAX_CARD_PURCHASE_LIMIT;
    }

    /**
     * @dev 'getMinCardPurchaseLimit' returns the lower limit of cards that can be purchased
     */
    function getMinCardPurchaseLimit() external pure returns (uint32) {
        return MIN_CARD_PURCHASE_LIMIT;
    }

    // ----INTERNAL--PRIVATE--PURE----
    /**
     * @dev '_prepareForMinting' is an internal function that can only be called by '_fulfillPcgCardsPurchase'
     * @dev This function is used to prepare the arrays of ids and the amounts to be minted
     * @dev By taking the random numbers that vrf returned it calculates the ids and for each id it adds an amount of 1
     * @dev The arrays have the same length and they can have from 1 to 'CARD_PURCHASE_LIMIT' slots
     * @dev Note that the id array can have multiple of the same id e.g. [2,0,2]
     * @dev The amounts array will always have 1 e.g. [1,1,1]
     * @dev The result of the two arrays that given in examples will be:
     * card id: 2, amount: 1
     * card id: 0, amount: 1
     * card id: 2, amount: 1
     * That is the reason that the arrays will have the same size
     * @dev NOTE: It would be more optimal to have the amount increased if the same id exist instead
     * of having the same id appear multiple times in the array, but memory arrays have fixed length in
     * solidity and it would be way more complex with more possibilities of errors to have the first approach
     * @param _randomWords is an array of random uint256 numbers which are used to find the ids of the cards to be minted
     * @param _numberOfMintableCards is the number of mintable cards of the chosen PCG expansion
     * @dev Code Explanation:
     * @dev Creates two arrays with length equal length of the array of random numbers one for the ids and one for the amonts
     * @dev then for each random number in the array of random numbers
     * @dev takes the divided balance of the random number divided by the number of mintable cards
     * @dev adds the divided balance to the array of ids that will be minted
     * This works because the divided balance will alway be lower the number of mintable cards
     * also the number of mintable cards cannot be 0
     * Example: random number: 1002, number of mintable cards: 10 -> id to be minted : 1002 % 10 = 2
     * @dev adds 1 to the array of amounts
     * @dev after this process is done for every random number it returns the two arrays
     */
    function _prepareForMinting(uint256[] memory _randomWords, uint256 _numberOfMintableCards)
        internal
        pure
        returns (uint256[] memory, uint256[] memory)
    {
        uint256[] memory cardIdsToMint = new uint256[](_randomWords.length);
        uint256[] memory amountsToMint = new uint256[](_randomWords.length);
        for (uint256 i = 0; i < _randomWords.length; i++) {
            uint256 _cardIdToTransfer = _randomWords[i] % _numberOfMintableCards;
            cardIdsToMint[i] = _cardIdToTransfer;
            amountsToMint[i] = 1;
        }
        return (cardIdsToMint, amountsToMint);
    }
}
