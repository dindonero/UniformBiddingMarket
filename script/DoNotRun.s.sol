// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {DeployerEnergyBiddingMarket} from "./EnergyBiddingMarket.s.sol";


contract DoNotRun is Script {

    function run() public {

        //DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
        //EnergyBiddingMarket market = deployer.run();
        EnergyBiddingMarket market = EnergyBiddingMarket(0x2A9510Ae0aD44955b5749b3b9f31707F8D459529);
        uint256 correctHour = (block.timestamp / 3600) * 3600 + 3600; // first math is to get the current exact hour
        uint256 minimumPrice = market.MIN_PRICE();

        vm.startBroadcast();

        uint256 loops = 100;
        // Generate random bids and asks
        uint256 totalBidAmount = 0;
        uint256 totalAskAmount = 0;
        uint256 bidPrice = minimumPrice + 1e9;
        uint256 smallAskAmount = 1;
        uint256 smallBidAmount = 2;

        // Place random bids
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomBidAmount = smallBidAmount + (i * 2); // Increment to vary the bid amounts
            market.placeBid{value: (bidPrice - i) * randomBidAmount}(correctHour, randomBidAmount); // change to bidPrice + i to test for the worst case possible
            totalBidAmount += randomBidAmount;
        }

        //vm.warp(correctHour + 1);

        // Place random asks
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomAskAmount = smallAskAmount + i; // Increment to vary the ask amounts
            market.placeAsk(randomAskAmount, address(this));
            totalAskAmount += randomAskAmount;
        }

        //vm.warp(correctHour + 3601);

        // Attempt to clear the market
        //market.clearMarket(correctHour);
        vm.stopBroadcast();

    }
}