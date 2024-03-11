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

    function test_placeBid() public {
        market.placeBid(correctHour, 100, minimumPrice);
    }

    function test_placeBid_wrongHour() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__WrongHourProvided.selector, correctHour + 1));
        market.placeBid(correctHour + 1, 100, 100);
    }

    function test_placeBid_hourInPast() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__WrongHourProvided.selector, correctHour - 3600));
        market.placeBid(correctHour - 3600, 100, 100);
    }

    function test_placeBid_lessThanMinimumPrice() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__BidMinimumPriceNotMet.selector, 100, 10000));
        market.placeBid(correctHour, 100, 100);
    }

    function test_placeBid_amountZero() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyBiddingMarket__AmountCannotBeZero.selector, 0));
        market.placeBid(correctHour, 0, minimumPrice);
    }
}
