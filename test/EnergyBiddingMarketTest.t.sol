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
    uint256 askHour;
    uint256 clearHour;
    uint256 minimumPrice;

    function setUp() public {
        DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
        market = deployer.run();
        eurc = EURC(address(market.EURC()));
        correctHour = (block.timestamp / 3600) * 3600 + 3600; // first math is to get the current exact hour
        askHour = correctHour + 1;
        clearHour = askHour + 3601;
        minimumPrice = market.MIN_PRICE();

        eurc.mint(10 ** 20);
        eurc.approve(address(market), type(uint256).max);
        eurc.transfer(address(0xBEEF), 10 ** 18);

        vm.prank(address(0xBEEF));
        eurc.approve(address(market), type(uint256).max);

        vm.stopPrank();
    }

    function test_placeBid_Success() public {
        market.placeBid(correctHour, 100, minimumPrice);
        (address bidder, uint256 amount, uint256 price, bool settled) = market
            .bidsByHour(correctHour, 0);
        assertEq(amount, 100);
        assertEq(price, minimumPrice);
        assertEq(settled, false);
        assertEq(bidder, address(this));
    }

    function test_placeBid_wrongHour() public {
        uint256 wrongHour = correctHour + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHourProvided.selector,
                wrongHour
            )
        );
        market.placeBid(wrongHour, 100, 100);
    }

    function test_placeBid_hourInPast() public {
        uint256 wrongHour = correctHour - 3600;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHourProvided.selector,
                wrongHour
            )
        );
        market.placeBid(wrongHour, 100, 100);
    }

    function test_placeBid_lessThanMinimumPrice() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__BidMinimumPriceNotMet.selector,
                100,
                10000
            )
        );
        market.placeBid(correctHour, 100, 100);
    }

    function test_placeBid_amountZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeBid(correctHour, 0, minimumPrice);
    }

    function test_placeAsk_Success() public {
        vm.warp(askHour);
        uint256 askAmount = 100;
        market.placeAsk(correctHour, askAmount);
        (
            address seller,
            uint256 amount,
            uint256 matchedAmount,
            bool settled
        ) = market.asksByHour(correctHour, 0);
        assertEq(amount, askAmount);
        assertEq(settled, false);
        assertEq(seller, address(this));
        assertEq(matchedAmount, 0);
    }

    function test_placeAsk_WrongHour() public {
        vm.warp(askHour);
        uint256 wrongHour = correctHour + 1;
        uint256 amount = 100;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHourProvided.selector,
                wrongHour
            )
        );
        market.placeAsk(wrongHour, amount);
    }

    function test_placeAsk_AmountZero() public {
        vm.warp(askHour);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeAsk(correctHour, 0);
    }

    function test_claimBalance_NoBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoClaimableBalance.selector,
                address(this)
            )
        );
        market.claimBalance();
    }

    function test_clearMarket_NoBidsOrAsks() public {
        vm.warp(clearHour);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoBidsOrAsksForThisHour.selector,
                correctHour
            )
        );
        market.clearMarket(correctHour);
    }

    function test_clearMarket_NoBids() public {
        vm.warp(askHour);
        // Setup: Place an ask but no bids
        uint256 amount = 1000;
        market.placeAsk(correctHour, amount);

        // Attempt to clear the market for the hour with no bids
        vm.warp(clearHour);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoBidsOrAsksForThisHour.selector,
                correctHour
            )
        );
        market.clearMarket(correctHour);
    }

    function test_clearMarket_NoAsks() public {
        // Setup: Place a bid but no asks
        uint256 amount = 1000;
        market.placeBid(correctHour, amount, minimumPrice);

        // Attempt to clear the market for the hour with no asks
        vm.warp(clearHour);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoBidsOrAsksForThisHour.selector,
                correctHour
            )
        );
        market.clearMarket(correctHour);
    }

    function test_clearMarket_bigAskSmallBids() public {
        // Setup

        // Place several small bids that together don't cover the big ask
        uint256 smallBidAmount = 100;
        uint256 bidPrice = market.MIN_PRICE();
        for (int i = 0; i < 50; i++) {
            // Total bid amount = 5000, less than the ask
            market.placeBid(correctHour, smallBidAmount, bidPrice);
        }

        vm.warp(askHour);
        uint256 bigAskAmount = 10000;
        market.placeAsk(correctHour, bigAskAmount);

        // Attempt to clear the market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        uint256 expectedMatchedAmount = 5000;

        (, , uint256 matchedAmount, bool settled) = market.asksByHour(
            correctHour,
            0
        );
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
        vm.warp(askHour);
        uint256 smallAskAmount = 100;
        for (int i = 0; i < 50; i++) {
            // Total ask amount = 5000, less than the bid
            market.placeAsk(correctHour, smallAskAmount);
        }

        // Attempt to clear the market
        // The expectation here depends on your market clearing logic.
        vm.warp(clearHour);
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

        vm.warp(askHour);
        // Place random asks
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomAskAmount = smallAskAmount + i; // Increment to vary the ask amounts
            market.placeAsk(correctHour, randomAskAmount);
            totalAskAmount += randomAskAmount;
        }

        // Attempt to clear the market
        vm.warp(clearHour);
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
            (, amount, amountMatched, settled) = market.asksByHour(
                correctHour,
                i
            );
            if (actualTotalAskAmount < totalMatchedAmount) {
                assertEq(
                    amountMatched,
                    settled
                        ? smallAskAmount + i
                        : totalMatchedAmount - actualTotalAskAmount
                ); // Each settled ask should match its asked amount
                bool settledOrPartiallySettled = settled ||
                    (!settled && (amountMatched < amount));
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

    function test_getBidsByHour() public {
        uint256 amount = 100;
        uint256 bidPrice = market.MIN_PRICE();
        market.placeBid(correctHour, amount, bidPrice);
        EnergyBiddingMarket.Bid[] memory bids = market.getBidsByHour(
            correctHour
        );
        assertEq(bids[0].bidder, address(this));
        assertEq(bids[0].amount, amount);
        assertEq(bids[0].price, bidPrice);
        assertEq(bids[0].settled, false);
        assertEq(bids.length, 1);
    }

    function test_getAsksByHour() public {
        vm.warp(askHour);
        uint256 amount = 100;
        market.placeAsk(correctHour, amount);
        EnergyBiddingMarket.Ask[] memory asks = market.getAsksByHour(
            correctHour
        );
        assertEq(asks[0].seller, address(this));
        assertEq(asks[0].amount, amount);
        assertEq(asks[0].settled, false);
        assertEq(asks.length, 1);
    }

    // in this function multiple bids are placed by different addresses and then we check if the function returns the correct bids by address
    function test_getAsksByAddress() public {
        vm.warp(askHour);
        // Setup: Place multiple asks by different addresses
        vm.prank(address(0xBEEF));
        market.placeAsk(correctHour, 100);

        vm.stopPrank();
        market.placeAsk(correctHour, 200);

        vm.prank(address(0xBEEF));
        market.placeAsk(correctHour, 50);

        // Act: Retrieve asks by specific address
        EnergyBiddingMarket.Ask[] memory beefAsks = market.getAsksByAddress(
            correctHour,
            address(0xBEEF)
        );

        // Assert: Check correct filtering
        assertEq(beefAsks.length, 2);
        assertEq(beefAsks[0].seller, address(0xBEEF));
        assertEq(beefAsks[0].amount, 100);
        assertEq(beefAsks[1].seller, address(0xBEEF));
        assertEq(beefAsks[1].amount, 50);

        // Additional checks to ensure no asks from other addresses are included
        for (uint i = 0; i < beefAsks.length; i++) {
            assertEq(beefAsks[i].seller, address(0xBEEF));
        }
    }

    function test_getBidsByAddress() public {
        // Setup: Place multiple bids by different addresses
        uint256 price = 100000; // 0.1 EURC assuming 6 decimal places for the token

        vm.prank(address(0xBEEF));
        market.placeBid(correctHour, 100, price); // Address 0xBEEF places a bid

        vm.stopPrank();
        market.placeBid(correctHour, 200, price); // Address 0xDEAD places another bid

        vm.prank(address(0xBEEF));
        market.placeBid(correctHour, 50, price); // Address 0xBEEF places another bid

        // Act: Retrieve bids by specific address
        EnergyBiddingMarket.Bid[] memory beefBids = market.getBidsByAddress(
            correctHour,
            address(0xBEEF)
        );

        // Assert: Check correct filtering
        assertEq(beefBids.length, 2);
        assertEq(beefBids[0].bidder, address(0xBEEF));
        assertEq(beefBids[0].amount, 100);
        assertEq(beefBids[0].price, price);
        assertEq(beefBids[1].bidder, address(0xBEEF));
        assertEq(beefBids[1].amount, 50);
        assertEq(beefBids[1].price, price);

        // Additional checks to ensure no bids from other addresses are included
        for (uint i = 0; i < beefBids.length; i++) {
            assertEq(beefBids[i].bidder, address(0xBEEF));
        }
    }

    function test_placeMultipleBids_Success() public {
        uint256 beginHour = correctHour;
        uint256 endHour = correctHour + 7200; // 2 hours range
        uint256 amount = 100;
        uint256 price = minimumPrice;

        market.placeMultipleBids(beginHour, endHour, amount, price);

        for (uint256 hour = beginHour; hour < endHour; hour += 3600) {
            (
                address bidder,
                uint256 bidAmount,
                uint256 bidPrice,
                bool settled
            ) = market.bidsByHour(hour, 0);
            assertEq(bidAmount, amount);
            assertEq(bidPrice, price);
            assertEq(settled, false);
            assertEq(bidder, address(this));
        }
    }
}
