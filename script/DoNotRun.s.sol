/*// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {EURC} from "../src/token/EURC.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {DeployerEnergyBiddingMarket} from "./EnergyBiddingMarket.s.sol";


contract DoNotRun is Script {

    function run() public {

        DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
        EnergyBiddingMarket market = deployer.run();
        EURC eurc = EURC(address(market.EURC()));
        uint256 correctHour = (block.timestamp / 3600) * 3600 + 3600; // first math is to get the current exact hour
        uint256 minimumPrice = market.MIN_PRICE();

        vm.startBroadcast();

        eurc.approve(address(market), type(uint256).max);

        uint256 loops = 1000;
        // Generate random bids and asks
        uint256 totalBidAmount = 0;
        uint256 totalAskAmount = 0;
        uint256 bidPrice = minimumPrice;
        uint256 smallAskAmount = 10;
        uint256 smallBidAmount = 20;

        // Place random bids
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomBidAmount = smallBidAmount + (i * 2); // Increment to vary the bid amounts
            market.placeBid(correctHour, randomBidAmount, bidPrice + i);
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
        vm.stopBroadcast();

    }
}*/