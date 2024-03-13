// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/EnergyBiddingMarket.sol";
import {EURC} from "../src/token/EURC.sol";
import {DeployerEnergyBiddingMarket} from "../script/EnergyBiddingMarket.s.sol";

contract EnergyBiddingMarketTest is Test {
    EnergyBiddingMarket market;
    EURC eurc;
    uint256 correctHour;
    uint256 minimumPrice;

    function setUp() public {
        DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
        market = deployer.run();
        eurc = EURC(address(market.EURC()));
        correctHour = (block.timestamp / 3600) * 3600 + 3600; // first math is to get the current exact hour
        minimumPrice = market.MIN_PRICE();

        eurc.mint(type(uint256).max);
        eurc.approve(address(market), type(uint256).max);
    }

    function test_placeBid_Success() public {
        market.placeBid(correctHour, 100, minimumPrice);
        (address bidder, uint256 amount, uint256 price, bool settled) = market.bidsByHour(correctHour, 0);
        assertEq(amount, 100);
        assertEq(price, minimumPrice);
        assertEq(settled, false);
        assertEq(bidder, address(this));
    }

    function test_placeBid_wrongHour() public {
        uint256 wrongHour = correctHour + 1;
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__WrongHourProvided.selector, wrongHour));
        market.placeBid(wrongHour, 100, 100);
    }

    function test_placeBid_hourInPast() public {
        uint256 wrongHour = correctHour - 3600;
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__WrongHourProvided.selector, wrongHour));
        market.placeBid(wrongHour, 100, 100);
    }

    function test_placeBid_lessThanMinimumPrice() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__BidMinimumPriceNotMet.selector, 100, 10000));
        market.placeBid(correctHour, 100, 100);
    }

    function test_placeBid_amountZero() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__AmountCannotBeZero.selector));
        market.placeBid(correctHour, 0, minimumPrice);
    }

    function test_placeAsk_Success() public {
        uint256 askAmount = 100;
        market.placeAsk(correctHour, askAmount);
        (address seller, uint256 amount, uint256 matchedAmount, bool settled) = market.asksByHour(correctHour, 0);
        assertEq(amount, askAmount);
        assertEq(settled, false);
        assertEq(seller, address(this));
        assertEq(matchedAmount, 0);
    }

    function test_placeAsk_WrongHour() public {
        uint256 wrongHour = correctHour + 1;
        uint256 amount = 100;
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__WrongHourProvided.selector, wrongHour));
        market.placeAsk(wrongHour, amount);
    }

    function test_placeAsk_AmountZero() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__AmountCannotBeZero.selector));
        market.placeAsk(correctHour, 0);
    }

    function test_claimBalance_NoBalance() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__NoClaimableBalance.selector, address(this)));
        market.claimBalance();
    }

    function test_clearMarket_NoBidsOrAsks() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__NoBidsOrAsksForThisHour.selector, correctHour));
        market.clearMarket(correctHour);
    }

    function test_clearMarket_NoBids() public {
        // Setup: Place an ask but no bids
        uint256 amount = 1000;
        market.placeAsk(correctHour, amount);

        // Attempt to clear the market for the hour with no bids
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__NoBidsOrAsksForThisHour.selector, correctHour));
        market.clearMarket(correctHour);
    }

    function test_clearMarket_NoAsks() public {
        // Setup: Place a bid but no asks
        uint256 amount = 1000;
        market.placeBid(correctHour, amount, minimumPrice);

        // Attempt to clear the market for the hour with no asks
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__NoBidsOrAsksForThisHour.selector, correctHour));
        market.clearMarket(correctHour);
    }

    function test_clearMarket_bigAskSmallBids() public {
        // Setup: Place a large ask
        uint256 bigAskAmount = 10000;
        market.placeAsk(correctHour, bigAskAmount);

        // Place several small bids that together don't cover the big ask
        uint256 smallBidAmount = 100;
        uint256 bidPrice = market.MIN_PRICE();
        for (int i = 0; i < 50; i++) { // Total bid amount = 5000, less than the ask
            market.placeBid(correctHour, smallBidAmount, bidPrice);
        }

        // Attempt to clear the market
        // The expectation here depends on your market clearing logic. If your logic allows for partial fulfillment,
        // this may not revert. If it requires full fulfillment, you'd expect a revert or a specific outcome.
        market.clearMarket(correctHour);

        uint256 expectedMatchedAmount = 5000;

        (, , uint256 matchedAmount, bool settled) = market.asksByHour(correctHour, 0);
        assertEq(settled, false);
        assertEq(matchedAmount, expectedMatchedAmount);
    }


    function test_clearMarket_smallBidSmallAsks() public {
        // Setup: Place a large bid
        uint256 bigBidAmount = 1000;
        uint256 bidPrice = market.MIN_PRICE();
        market.placeBid(correctHour, bigBidAmount, bidPrice);

        // Place several small asks
        uint256 smallAskAmount = 100;
        for (int i = 0; i < 50; i++) { // Total ask amount = 5000, less than the bid
            market.placeAsk(correctHour, smallAskAmount);
        }

        // Attempt to clear the market
        // The expectation here depends on your market clearing logic.
        market.clearMarket(correctHour);

        // Add assertions here to verify the state after attempting to clear the market
        // Check if the big bid was partially fulfilled, if the asks were all fulfilled, and the clearing price
    }
}
