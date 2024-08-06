//SPDX-License-Identifier: MIT

//VERSION
pragma solidity 0.8.20;

// IMPORTS
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// LIBRARIES
/**
 * @title Price Converter
 * @author John Christidis
 * @notice This is a library used to uint256 in PCGEngine to calculate the price of native currency in euro
 * and the opposite. This is used to calculate and estimate prices of ERC1155 cards that have a constant price in euros.
 * @dev It uses the 'AggregatorV3Interface' of chainlink to get the prices of native currency in usd and
 * the price euro in usd since there is no direct convertion.
 */
library PriceConverter {
    // --FUNCTIONS--
    // ----INTERNAL--PRIVATE--VIEW----

    /**
     * @dev 'getPrice' is a function that calls the 'AggregatorV3Interface' with a price feed address from chainlink
     * to get the price conversion of two prices
     * @dev This project uses it with the pricefeeds from the native currency to usd and and euro to usd since there is
     * no deirect pricefeed conversion address.
     * @param _priceFeedAddress is the address of the contract that updates the pricefeeds every x time (chainlink docs)
     * @dev Code Explanation:
     * @dev Calls the pricefeed contract
     * @dev Calls the function 'latestRoundData' that returns the price which is an integer
     * @dev Calls the function that returns the decimals which are digits in uints (this is explained in the example bellow)
     * @dev Finds the missing decimals so that the result will be returned with the correct number of digits
     * @dev Checks if price is negative and if it is returns 0 (This will be used later)
     * @dev Returns price multiplied by 10 power of the missing decimals
     * @dev EXAMPLE:
     * Price of Ether in Usd -> 1 ETH is 3000 USD
     * the function 'latestRoundData' returns the price like this: 3000_0000_0000
     * this is the price 3000 followed by 8 zeroes: 3000_0000_0000
     * this 8 zeroes represent the decimal points of the conversion and since the uints and ints don't have decimals
     * they are returned as digits.
     * However each pricefeed returns with a different number of decimal digits
     * e.g. Ether to Usd -> 8 decimals
     *      Btc   to Usd -> 10 decimals
     * So the 'AggregatorV3Interface' has the function 'decimals' to get the decimals for each pricefeed
     * But the price of a card is x * 10^18 so there is a need to turn the pricefeed to an 18 digit uint
     * so for eth to usd would be 18 - decimals = 18 - 8 = 10 extra digits
     * so finally the price for eth to usd is 3000_0000_0000 * 10^10 = 3000_000_000_000_000_000_000
     *
     * @dev RESULTS found from fuzzing
     * @dev getPrice breaks when a price that is returned is really high. anything bellow a uint96.max is fine
     * @dev We can consider using uncheck and then check for overflow ourselves
     * @dev We can consider adding a try/catch to ensure that this function will work properly but we consider gas consumption
     * @dev This function is used to a purchase function making it inefficient to add try/catch
     */
    function getPrice(address _priceFeedAddress) internal view returns (uint256) {
        AggregatorV3Interface _priceFeed = AggregatorV3Interface(_priceFeedAddress);
        (, int256 price,,,) = _priceFeed.latestRoundData();
        uint256 decimals = _priceFeed.decimals();
        uint256 totalDecimals = 18;
        uint256 missingDecimals = totalDecimals - decimals;
        if (price <= 0) {
            return 0;
        }
        return (uint256(price) * 10 ** missingDecimals);
    }
    /**
     * @dev 'getNativeToEurPrice' is a function that uses 'getPrice' twice function to get the conversion of the
     * native currency to euro since there is no direct conversion.
     * @dev In case the pricefeeds return invalid answers like negative numbers or zero there is this function
     * takes into account the last price conversion and this is what is using.
     * @param _nativeToUsdPriceFeedAddress is the address of the pricefeed contract for the native currency to usd
     * @param _eurToUsdPriceFeedAddress is the address of the pricefeed contract for euro to usd
     * @param _lastPriceConversion is the last successful convertion made and is passed as a parameter to be used
     * in case of a problem with the pricefeeds
     * (WEAK POINT this should at least be used succesfuly once else the system breaks)
     * @dev Code Explanation:
     * @dev uses 'getPrice' to get the price of native to usd and eur to usd
     * @dev Check if any of them are 0 or negative. if yes, it returns the last price conversion
     * @dev Else it makes the conversion from native to euro
     * @dev Check if the conversion is 0 which could result if nativeToUsd price is much smaller than eurToUsd price
     * @dev If it is retrns last price conversion
     * @dev else returns the new price
     * @dev Math Example with fake numbers:
     * ETH to USD -> 3000 -> 'getPrice' function will return 3000_000_000_000_000_000_000
     * EUR to USD -> 1.5  -> 'getPrice' function will return 1_500_000_000_000_000_000
     * ETH to EUR -> 3000_000_000_000_000_000_000 / 1_500_000_000_000_000_000 = 2000
     * But that need to be with 18 decimals so 2000 * 1e18 = 2000_000_000_000_000_000_000
     * And this is the returning result
     */

    function getNativeToEurPrice(
        address _nativeToUsdPriceFeedAddress,
        address _eurToUsdPriceFeedAddress,
        uint256 _lastPriceConversion
    ) internal view returns (uint256) {
        uint256 nativeToUsdPrice = getPrice(_nativeToUsdPriceFeedAddress);
        uint256 eurToUsdPrice = getPrice(_eurToUsdPriceFeedAddress);
        if (nativeToUsdPrice <= 0 || eurToUsdPrice <= 0) {
            return (_lastPriceConversion);
        }
        uint256 _nativeToEurPrice = (nativeToUsdPrice * 1e18) / eurToUsdPrice;
        if (_nativeToEurPrice <= 0) {
            return (_lastPriceConversion);
        }
        return (_nativeToEurPrice);
    }
    /**
     * @dev 'getConversionRate' is the function used in uint256 that represent currency in native to convert them in euro
     * @param _amount is the amount of euro to change to native (note: when used as a library it is automatically added as a parameter)
     * @param _nativeToUsdPriceFeedAddress is the address of the pricefeed contract for the native currency to usd
     * @param _eurToUsdPriceFeedAddress is the address of the pricefeed contract for euro to usd
     * @param _lastPriceConversion is the last successful convertion made and is passed as a parameter to be used
     * This is just passed to the 'getNativeToEurPrice' as in libraries, variables cannot be stored
     * @dev Code explanation:
     * @dev Uses 'getNativeToEurPrice' to get the native currency's price in euro
     * @dev Multiplies it with the amount to find amount price in euro
     * @dev EXAMPLE: Amount : 0.001 ETHER
     *      1 ETHER = 1*10^18 wei ->  EURO : 2000*10^18 (In wei because this is how it used in payable functions)
     *  0.001 ETHER = 1*10^15 wei ->  EURO : x
     *  x = 2000*10^18 * 1*10^15 / 1*10^18 = 2000*10^15
     * @dev Returns price of amount in euro and price of ether in euro
     */

    function getConversionRate(
        uint256 _amount,
        address _nativeToUsdPriceFeedAddress,
        address _eurToUsdPriceFeedAddress,
        uint256 _lastPriceConversion
    ) internal view returns (uint256, uint256) {
        (uint256 nativeToEurPrice) =
            getNativeToEurPrice(_nativeToUsdPriceFeedAddress, _eurToUsdPriceFeedAddress, _lastPriceConversion);
        uint256 nativeAmountInEur = (nativeToEurPrice * _amount) / 1e18; //open-fuzz: this can make an overflow if the msg.value they put is too big
        return (nativeAmountInEur, nativeToEurPrice);
    }

    /**
     * @dev 'getReverseConversionRate' is used to get the amount euro in native which is useful to estimate the price of cards
     * @param _amount is the amount of native curency to change in euro (note: when used as a library it is automatically added as a parameter)
     * @param _nativeToUsdPriceFeedAddress is the address of the pricefeed contract for the native currency to usd
     * @param _eurToUsdPriceFeedAddress is the address of the pricefeed contract for euro to usd
     * @param _lastPriceConversion is the last successful convertion made and is passed as a parameter to be used
     * This is just passed to the 'getNativeToEurPrice' as in libraries, variables cannot be stored
     * @dev Code explanation:
     * @dev Uses 'getNativeToEurPrice' to get the native currency's price in euro
     * @dev Calculates the price of amount in native
     * @dev EXAMPLE Amount : EURO -> 2*10^18
     *      1 ETHER = 1*10^18 wei ->  EURO : 2000*10^18 (In wei because this is how it used in payable functions)
     *      x ETHER =      x' wei ->  EURO :    2*10^18
     *  x' = 2*10^18 * 1*10^18 / 2000*10^18 = 1*10^15
     * @dev Returns price of amount in native currency
     */
    function getReverseConversionRate(
        uint256 _amount,
        address _nativeToUsdPriceFeedAddress,
        address _eurToUsdPriceFeedAddress,
        uint256 _lastPriceConversion
    ) internal view returns (uint256) {
        (uint256 nativeToEurPrice) =
            getNativeToEurPrice(_nativeToUsdPriceFeedAddress, _eurToUsdPriceFeedAddress, _lastPriceConversion);
        uint256 eurAmountInNative = (1e18 * _amount) / nativeToEurPrice;
        return eurAmountInNative;
    }
}
