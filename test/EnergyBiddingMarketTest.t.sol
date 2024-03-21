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
        market.clearMarket(correctHour);

        uint256 expectedMatchedAmount = 5000;

        (, , uint256 matchedAmount, bool settled) = market.asksByHour(correctHour, 0);
        assertEq(settled, false);
        assertEq(matchedAmount, expectedMatchedAmount);
        for (uint256 i = 0; i < 50; i++) {
            (, matchedAmount, , settled) = market.bidsByHour(correctHour, i);
            assertEq(settled, true);
        }
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

        // bid should be settled
        (, , , bool settled) = market.bidsByHour(correctHour, 0);
        assertEq(settled, true);

        uint256 amountMatched;

        // 10 first asks should be settled and the rest shouldn't
        for (uint256 i = 0; i < 10; i++) {
            (, , amountMatched, settled) = market.asksByHour(correctHour, i);
            assertEq(settled, true);
            assertEq(amountMatched, smallAskAmount);
        }
        for (uint256 i = 10; i < 50; i++) {
            (, , amountMatched, settled) = market.asksByHour(correctHour, i);
            assertEq(settled, false);
            assertEq(amountMatched, 0);
        }
    }

    function test_clearMarket_randomBidsAndAsks() public {

        uint256 loops = 100;
        // Generate random bids and asks
        uint256 totalBidAmount = 0;
        uint256 totalAskAmount = 0;
        uint256 bidPrice = market.MIN_PRICE();
        uint256 smallAskAmount = 10;
        uint256 smallBidAmount = 20;

        // Place random bids
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomBidAmount = smallBidAmount + (i * 2); // Increment to vary the bid amounts
            market.placeBid(correctHour, randomBidAmount, bidPrice + i); // Increment to vary the bid prices
            totalBidAmount += randomBidAmount;
        }

        // Place random asks
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomAskAmount = smallAskAmount + i; // Increment to vary the ask amounts
            market.placeAsk(correctHour, randomAskAmount);
            totalAskAmount += randomAskAmount;
        }

        // Attempt to clear the market
        market.clearMarket(correctHour);

        // Verify the settled status and amount matched for bids and asks
        uint256 amountMatched;
        bool settled;
        uint256 amount;
        uint256 matchedBids = 0;
        uint256 totalMatchedAmount = 0;
        uint256 bidAmount;

        // Check bids
        for (uint256 i = 0; i < loops; i++) {
            (, bidAmount, , settled) = market.bidsByHour(correctHour, i);
            if (settled) {
                matchedBids++;
                totalMatchedAmount += bidAmount;
            }
        }

        // The total matched amount should not exceed the total bid amount
        assert(totalMatchedAmount <= totalBidAmount);

        // Check asks
        uint256 settledAsks = 0;
        uint256 actualTotalAskAmount = 0; 
        for (uint256 i = 0; i < loops; i++) {
            (, amount, amountMatched, settled) = market.asksByHour(correctHour, i);
            if (actualTotalAskAmount < totalMatchedAmount) {
                assertEq(amountMatched, settled ? smallAskAmount + i : totalMatchedAmount - actualTotalAskAmount); // Each settled ask should match its asked amount
                bool settledOrPartiallySettled = settled || (!settled && (amountMatched < amount));
                assert(settledOrPartiallySettled);
                settledAsks++;
                actualTotalAskAmount += amountMatched;
            } else {
                assertEq(amountMatched, 0); // Unsettled asks should have no amount matched
            }
        }

        assertEq(actualTotalAskAmount, totalMatchedAmount);

        // The number of settled asks should be less than or equal to the total number of asks
        assert(settledAsks <= loops);
    }

}
