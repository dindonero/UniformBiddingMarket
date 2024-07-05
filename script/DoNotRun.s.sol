// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {DeployerEnergyBiddingMarket} from "./EnergyBiddingMarket.s.sol";


contract DoNotRun is Script {

    function run() public {

        DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
        EnergyBiddingMarket market = deployer.run();
        uint256 correctHour = (block.timestamp / 3600) * 3600 + 3600; // first math is to get the current exact hour
        uint256 minimumPrice = market.MIN_PRICE();

        vm.startBroadcast();

        uint256 loops = 5000;
        // Generate random bids and asks
        uint256 totalBidAmount = 0;
        uint256 totalAskAmount = 0;
        uint256 bidPrice = minimumPrice + 100000000;
        uint256 smallAskAmount = 10;
        uint256 smallBidAmount = 20;

        // Place random bids
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomBidAmount = smallBidAmount + (i * 2); // Increment to vary the bid amounts
            market.placeBid{value: (bidPrice - i) * randomBidAmount}(correctHour, randomBidAmount); // change to bidPrice + i to test for the worst case possible
            totalBidAmount += randomBidAmount;
        }

        vm.warp(correctHour + 1);

        // Place random asks
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomAskAmount = smallAskAmount + i; // Increment to vary the ask amounts
            market.placeAsk(correctHour, randomAskAmount);
            totalAskAmount += randomAskAmount;
        }

        vm.warp(correctHour + 3601);

        // Attempt to clear the market
        market.clearMarket(correctHour);
        vm.stopBroadcast();

    }
}