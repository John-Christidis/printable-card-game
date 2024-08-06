//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PriceConverter} from "../../../src/libraries/PriceConverter.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract PriceConverterTest is Test {
    using PriceConverter for uint256;
    using PriceConverter for address;

    MockV3Aggregator nativeToUsdPriceFeed;
    MockV3Aggregator eurToUsdPriceFeed;

    uint8 NATIVE_TO_USD_DECIMALS = 8;
    int256 NATIVE_TO_USD_PRICE = 3000_0000_0000;

    uint8 EUR_TO_USD_DECIMALS = 8;
    int256 EUR_TO_USD_PRICE = 1_0000_0000;

    uint256 RETURNING_RESULT_MULTIPLIER = 1e10;

    int256 ZERO_PRICE = 0;
    int256 NEGATIVE_PRICE = -23;
    int256 VERY_BIG_PRICE = 3_311_426_648_430_842_910_303_114_327_700_000_000;

    uint256 lastPriceConversion;

    function setUp() external {
        lastPriceConversion = 2000e18;
        nativeToUsdPriceFeed = new MockV3Aggregator(NATIVE_TO_USD_DECIMALS, NATIVE_TO_USD_PRICE);
        eurToUsdPriceFeed = new MockV3Aggregator(EUR_TO_USD_DECIMALS, EUR_TO_USD_PRICE);
    }

    function test_PriceConverter_getPrice_returnsExpectedResult() external view {
        uint256 nativeToUsdPrice = address(nativeToUsdPriceFeed).getPrice();
        uint256 eurToUsdPrice = address(eurToUsdPriceFeed).getPrice();
        assertEq(nativeToUsdPrice, uint256(NATIVE_TO_USD_PRICE) * RETURNING_RESULT_MULTIPLIER);
        assertEq(eurToUsdPrice, uint256(EUR_TO_USD_PRICE) * RETURNING_RESULT_MULTIPLIER);
    }

    function test_PriceConverter_getPrice_returnsZeroIfPriceFeedsAreNegativeOrZero() external {
        nativeToUsdPriceFeed.updateAnswer(NEGATIVE_PRICE);
        uint256 nativeToUsdPrice = address(nativeToUsdPriceFeed).getPrice();
        eurToUsdPriceFeed.updateAnswer(ZERO_PRICE);
        uint256 eurToUsdPrice = address(eurToUsdPriceFeed).getPrice();
        assertEq(nativeToUsdPrice, uint256(ZERO_PRICE));
        assertEq(eurToUsdPrice, uint256(ZERO_PRICE));
    }

    function test_PriceConverter_getNativeToEurPrice_returnsExpectedResult() external view {
        uint256 nativeToEurPrice =
            address(nativeToUsdPriceFeed).getNativeToEurPrice(address(eurToUsdPriceFeed), lastPriceConversion);
        assertEq(nativeToEurPrice, uint256(NATIVE_TO_USD_PRICE) * RETURNING_RESULT_MULTIPLIER); // 3000e8 * 1e10
    }

    function test_PriceConverter_getNativeToEurPrice_returnsExpectedResultInCaseOfNegativeOrZeroDataFeedOnNativeToUsd()
        external
    {
        nativeToUsdPriceFeed.updateAnswer(NEGATIVE_PRICE);
        uint256 negativeNativeToEurPrice =
            address(nativeToUsdPriceFeed).getNativeToEurPrice(address(eurToUsdPriceFeed), lastPriceConversion);
        assertEq(negativeNativeToEurPrice, lastPriceConversion);
        nativeToUsdPriceFeed.updateAnswer(ZERO_PRICE);
        uint256 zeroNativeToEurPrice =
            address(nativeToUsdPriceFeed).getNativeToEurPrice(address(eurToUsdPriceFeed), lastPriceConversion);
        assertEq(zeroNativeToEurPrice, lastPriceConversion);
    }

    function test_PriceConverter_getNativeToEurPrice_returnsExpectedResultInCaseOfNegativeOrZeroDataFeedOnEurToUsd()
        external
    {
        eurToUsdPriceFeed.updateAnswer(NEGATIVE_PRICE);
        uint256 negativeNativeToEurPrice =
            address(nativeToUsdPriceFeed).getNativeToEurPrice(address(eurToUsdPriceFeed), lastPriceConversion);
        assertEq(negativeNativeToEurPrice, lastPriceConversion);
        eurToUsdPriceFeed.updateAnswer(ZERO_PRICE);
        uint256 zeroNativeToEurPrice =
            address(nativeToUsdPriceFeed).getNativeToEurPrice(address(eurToUsdPriceFeed), lastPriceConversion);
        assertEq(zeroNativeToEurPrice, lastPriceConversion);
    }

    function test_PriceConverter_getNativeToEurPrice_returnsLastPriceConversionWhenNativeToUsdPriceIsMuchSmallerThanEurToUsd(
    ) external {
        eurToUsdPriceFeed.updateAnswer(VERY_BIG_PRICE);
        uint256 lastPriceNativeToEurPrice =
            address(nativeToUsdPriceFeed).getNativeToEurPrice(address(eurToUsdPriceFeed), lastPriceConversion);
        assertEq(lastPriceNativeToEurPrice, lastPriceConversion);
    }

    function test_PriceConverter_getConversionRate_returnsExpectedResult() external view {
        uint256 amount = 1 ether;
        (uint256 nativeAmountInEur, uint256 newPriceConversion) =
            amount.getConversionRate(address(nativeToUsdPriceFeed), address(eurToUsdPriceFeed), lastPriceConversion);
        assertEq(newPriceConversion, uint256(NATIVE_TO_USD_PRICE) * RETURNING_RESULT_MULTIPLIER); //1e18 * 3000e8 * 1e10 / 1e18
        assertEq(nativeAmountInEur, uint256(NATIVE_TO_USD_PRICE) * RETURNING_RESULT_MULTIPLIER); //1e18 * 3000e8 * 1e10 / 1e18
    }

    function test_PriceConverter_getReverseConversionRate_returnsExpectedResult() external view {
        uint256 amount = 3e18;
        uint256 expectedResult = 1e15; // 3e18 * 1e18 / 3000e18

        uint256 eurAmountInNative = amount.getReverseConversionRate(
            address(nativeToUsdPriceFeed), address(eurToUsdPriceFeed), lastPriceConversion
        );
        assertEq(eurAmountInNative, expectedResult);
    }
}
