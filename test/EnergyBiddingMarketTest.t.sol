// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/EnergyBiddingMarket.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DeployerEnergyBiddingMarket} from "../script/EnergyBiddingMarket.s.sol";

contract EnergyBiddingMarketTest is Test {
    EnergyBiddingMarket market;
    uint256 correctHour;
    uint256 askHour;
    uint256 clearHour;
    uint256 minimumPrice;
    uint256 bidAmount;

    function setUp() public {
        DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();

        market = deployer.run();

        correctHour = (block.timestamp / 3600) * 3600 + 3600; // first math is to get the current exact hour
        askHour = correctHour + 1;
        clearHour = askHour + 3601;
        minimumPrice = market.MIN_PRICE();
        bidAmount = 100;

        vm.deal(address(0xBEEF), 1000 ether);
    }

    function test_placeBid_Success() public {
        market.placeBid{value: minimumPrice * bidAmount}(
            correctHour,
            bidAmount
        );
        (
            address bidder,
            bool settled,
            bool canceled,
            uint256 amount,
            uint256 price
        ) = market.bidsByHour(correctHour, 0);
        assertEq(amount, bidAmount);
        assertEq(price, minimumPrice);
        assertEq(settled, false);
        assertEq(bidder, address(this));
        assertEq(canceled, false);
    }

    function test_placeBid_wrongHour() public {
        uint256 wrongHour = correctHour + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHourProvided.selector,
                wrongHour
            )
        );
        market.placeBid{value: minimumPrice * bidAmount}(wrongHour, 100);
    }

    function test_placeBid_hourInPast() public {
        uint256 wrongHour = correctHour - 3600;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHourProvided.selector,
                wrongHour
            )
        );
        market.placeBid{value: minimumPrice * bidAmount}(wrongHour, 100);
    }

    function test_placeBid_lessThanMinimumPrice() public {
        uint256 wrongPrice = 100;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__BidMinimumPriceNotMet.selector,
                wrongPrice,
                minimumPrice
            )
        );
        market.placeBid{value: wrongPrice * bidAmount}(correctHour, bidAmount);
    }

    function test_placeBid_amountZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeBid{value: minimumPrice * bidAmount}(correctHour, 0);
    }

    function test_placeAsk_Success() public {
        vm.warp(askHour);
        uint256 askAmount = 100;
        market.placeAsk(askAmount, address(this));
        (
            address seller,
            bool settled,
            bool canceled,
            uint256 amount,
            uint256 matchedAmount
        ) = market.asksByHour(correctHour, 0);
        assertEq(amount, askAmount);
        assertEq(settled, false);
        assertEq(seller, address(this));
        assertEq(matchedAmount, 0);
        assertEq(canceled, false);
    }

    /*function test_placeAsk_WrongHour() public {
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
    }*/

    function test_placeAsk_AmountZero() public {
        vm.warp(askHour);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeAsk(0, address(this));
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
        market.placeAsk(amount, address(this));

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
        market.placeBid{value: minimumPrice * amount}(correctHour, amount);

        // Attempt to clear the market for the hour with no asks
        vm.warp(clearHour);

        market.clearMarket(correctHour);
        assertEq(market.balanceOf(address(this)), minimumPrice * amount);
    }

    function test_clearMarket_bigAskSmallBids() public {
        // Setup

        // Place several small bids that together don't cover the big ask
        uint256 smallBidAmount = 100;
        uint256 bidPrice = market.MIN_PRICE();
        for (int i = 0; i < 50; i++) {
            // Total bid amount = 5000, less than the ask
            market.placeBid{value: bidPrice * smallBidAmount}(
                correctHour,
                smallBidAmount
            );
        }

        vm.warp(askHour);
        uint256 bigAskAmount = 10000;
        market.placeAsk( bigAskAmount, address(this));

        // Attempt to clear the market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        uint256 expectedMatchedAmount = 5000;

        (, bool settled, , , uint256 matchedAmount) = market.asksByHour(
            correctHour,
            0
        );
        assertEq(settled, false);
        assertEq(matchedAmount, expectedMatchedAmount);
        for (uint256 i = 0; i < 50; i++) {
            (, settled, , , matchedAmount) = market.bidsByHour(correctHour, i);
            assertEq(settled, true);
        }
    }

    function test_clearMarket_smallBidSmallAsks() public {
        // Setup: Place a large bid
        uint256 bigBidAmount = 1000;
        uint256 bidPrice = market.MIN_PRICE();
        market.placeBid{value: bidPrice * bigBidAmount}(
            correctHour,
            bigBidAmount
        );

        // Place several small asks
        vm.warp(askHour);
        uint256 smallAskAmount = 100;
        for (int i = 0; i < 50; i++) {
            // Total ask amount = 5000, less than the bid
            market.placeAsk(smallAskAmount, address(this));
        }

        // Attempt to clear the market
        // The expectation here depends on your market clearing logic.
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // bid should be settled
        (, bool settled, , ,) = market.bidsByHour(correctHour, 0);
        assertEq(settled, true);

        uint256 amountMatched;

        // 10 first asks should be settled and the rest shouldn't
        for (uint256 i = 0; i < 10; i++) {
            (, settled, , , amountMatched) = market.asksByHour(correctHour, i);
            assertEq(settled, true);
            assertEq(amountMatched, smallAskAmount);
        }
        for (uint256 i = 10; i < 50; i++) {
            (, settled, , , amountMatched) = market.asksByHour(correctHour, i);
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
            market.placeBid{value: (bidPrice + i) * randomBidAmount}(
                correctHour,
                randomBidAmount
            ); // Increment to vary the bid prices
            totalBidAmount += randomBidAmount;
        }

        vm.warp(askHour);
        // Place random asks
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomAskAmount = smallAskAmount + i; // Increment to vary the ask amounts
            market.placeAsk(randomAskAmount, address(this));
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
        uint256 actualBidAmount;

        // Check bids
        for (uint256 i = 0; i < loops; i++) {
            (, settled, , actualBidAmount, ) = market.bidsByHour(correctHour, i);
            if (settled) {
                matchedBids++;
                totalMatchedAmount += actualBidAmount;
            }
        }

        // The total matched amount should not exceed the total bid amount
        assert(totalMatchedAmount <= totalBidAmount);

        // Check asks
        uint256 settledAsks = 0;
        uint256 actualTotalAskAmount = 0;
        for (uint256 i = 0; i < loops; i++) {
            (, settled, , amount, amountMatched) = market.asksByHour(
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
        uint256 bidPrice = market.MIN_PRICE();
        market.placeBid{value: bidPrice * bidAmount}(correctHour, bidAmount);
        EnergyBiddingMarket.Bid[] memory bids = market.getBidsByHour(
            correctHour
        );
        assertEq(bids[0].bidder, address(this));
        assertEq(bids[0].amount, bidAmount);
        assertEq(bids[0].price, bidPrice);
        assertEq(bids[0].settled, false);
        assertEq(bids.length, 1);
    }

    function test_getAsksByHour() public {
        vm.warp(askHour);
        uint256 amount = 100;
        market.placeAsk(amount, address(this));
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
        market.placeAsk(100, address(0xBEEF));

        vm.stopPrank();
        market.placeAsk(200, address(this));

        vm.prank(address(0xBEEF));
        market.placeAsk(50, address(0xBEEF));

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

        vm.prank(address(0xBEEF));
        market.placeBid{value: minimumPrice * bidAmount}(
            correctHour,
            bidAmount
        ); // Address 0xBEEF places a bid

        vm.stopPrank();
        market.placeBid{value: 200 * minimumPrice}(correctHour, 200); // Address 0xDEAD places another bid

        vm.prank(address(0xBEEF));
        market.placeBid{value: minimumPrice * 50}(correctHour, 50); // Address 0xBEEF places another bid

        // Act: Retrieve bids by specific address
        EnergyBiddingMarket.Bid[] memory beefBids = market.getBidsByAddress(
            correctHour,
            address(0xBEEF)
        );

        // Assert: Check correct filtering
        assertEq(beefBids.length, 2);
        assertEq(beefBids[0].bidder, address(0xBEEF));
        assertEq(beefBids[0].amount, 100);
        assertEq(beefBids[0].price, minimumPrice);
        assertEq(beefBids[1].bidder, address(0xBEEF));
        assertEq(beefBids[1].amount, 50);
        assertEq(beefBids[1].price, minimumPrice);

        // Additional checks to ensure no bids from other addresses are included
        for (uint i = 0; i < beefBids.length; i++) {
            assertEq(beefBids[i].bidder, address(0xBEEF));
        }
    }

    function test_placeMultipleRangedBids_Success() public {
        uint256 beginHour = correctHour;
        uint256 endHour = correctHour + 7200; // 2 hours range

        market.placeMultipleBids{value: minimumPrice * bidAmount * 2}(
            beginHour,
            endHour,
            bidAmount
        );

        for (uint256 hour = beginHour; hour < endHour; hour += 3600) {
            (
                address bidder,
                bool settled,
                bool canceled,
                uint256 actualBidAmount,
                uint256 bidPrice
            ) = market.bidsByHour(hour, 0);
            assertEq(actualBidAmount, bidAmount);
            assertEq(bidPrice, minimumPrice);
            assertEq(settled, false);
            assertEq(bidder, address(this));
            assertEq(canceled, false);
        }
    }

    function test_proxyUpgradability() public {
        // Deploy a new implementation contract
        EnergyBiddingMarket newImplementation = new EnergyBiddingMarket();

        // Upgrade the proxy to the new implementation
        UnsafeUpgrades.upgradeProxy(
            address(market),
            address(newImplementation),
            ""
        );

        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        bytes32 slotValue = vm.load(address(market), IMPLEMENTATION_SLOT);
        address retrievedImplementation = address(uint160(uint256(slotValue)));

        // Verify that the implementation address has been updated
        assertEq(retrievedImplementation, address(newImplementation));
    }

    function test_placeMultipleBids_Success() public {
        uint256[] memory biddingHours = new uint256[](2);
        biddingHours[0] = correctHour;
        biddingHours[1] = correctHour + 3600;

        market.placeMultipleBids{value: minimumPrice * bidAmount * 2}(
            biddingHours,
            bidAmount
        );

        for (uint256 i = 0; i < biddingHours.length; i++) {
            (
                address bidder,
                bool settled,
                bool canceled,
                uint256 actualBidAmount,
                uint256 bidPrice
            ) = market.bidsByHour(biddingHours[i], 0);
            assertEq(actualBidAmount, bidAmount);
            assertEq(bidPrice, minimumPrice);
            assertEq(settled, false);
            assertEq(bidder, address(this));
            assertEq(canceled, false);
        }
    }

    function test_placeMultipleBids_AmountZero() public {
        uint256[] memory biddingHours = new uint256[](2);
        biddingHours[0] = correctHour;
        biddingHours[1] = correctHour + 3600;

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeMultipleBids{value: minimumPrice * 2}(biddingHours, 0);
    }

    function test_placeMultipleBids_InvalidHours() public {
        uint256[] memory biddingHours = new uint256[](2);
        biddingHours[0] = correctHour;
        biddingHours[1] = correctHour + 1; // Invalid hour, not divisible by 3600

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHourProvided.selector,
                correctHour + 1
            )
        );
        market.placeMultipleBids{value: minimumPrice * bidAmount * 2}(
            biddingHours,
            bidAmount
        );
    }

    function test_placeMultipleBids_LessThanMinimumPrice() public {
        uint256[] memory biddingHours = new uint256[](2);
        biddingHours[0] = correctHour;
        biddingHours[1] = correctHour + 3600;

        uint256 wrongPrice = minimumPrice - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__BidMinimumPriceNotMet.selector,
                wrongPrice,
                minimumPrice
            )
        );
        market.placeMultipleBids{value: wrongPrice * bidAmount * 2}(
            biddingHours,
            bidAmount
        );
    }
    function test_cancelBid_Success() public {
        // Setup: Place a bid
        market.placeBid{value: minimumPrice * bidAmount}(
            correctHour,
            bidAmount
        );

        // Act: Cancel the bid
        market.cancelBid(correctHour, 0);

        // Assert: Check if the bid is marked as canceled
        (, , bool canceled, ,) = market.bidsByHour(correctHour, 0);
        assertEq(canceled, true);

        // Assert: Check if the claimable balance is updated correctly
        uint256 expectedBalance = bidAmount * minimumPrice;
        assertEq(market.claimableBalance(address(this)), expectedBalance);
    }

    function test_cancelBid_NotBidOwner() public {
        // Setup: Place a bid from a different address
        vm.prank(address(0xBEEF));
        market.placeBid{value: minimumPrice * bidAmount}(
            correctHour,
            bidAmount
        );

        // Act and Assert: Attempt to cancel the bid as a non-owner
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__OnlyBidOwnerCanCancel.selector,
                correctHour,
                address(this)
            )
        );
        market.cancelBid(correctHour, 0);
    }

    function test_cancelBid_MarketCleared() public {
        // Setup: Place a bid and clear the market
        market.placeBid{value: minimumPrice * bidAmount}(
            correctHour,
            bidAmount
        );
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // Act and Assert: Attempt to cancel the bid after the market is cleared
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__MarketAlreadyClearedForThisHour.selector,
                correctHour
            )
        );
        market.cancelBid(correctHour, 0);
    }

    function test_cancelBid_AlreadyCanceled() public {
        // Setup: Place a bid and cancel it
        market.placeBid{value: minimumPrice * bidAmount}(
            correctHour,
            bidAmount
        );
        market.cancelBid(correctHour, 0);

        // Act and Assert: Attempt to cancel the bid again
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__BidIsAlreadyCanceled.selector,
                correctHour,
                0
            )
        );
        market.cancelBid(correctHour, 0);
    }
}
