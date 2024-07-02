// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";

contract DeployerEnergyBiddingMarket is Script {

    function run() public returns (EnergyBiddingMarket) {
        EnergyBiddingMarket market;

        vm.startBroadcast();
        market = new EnergyBiddingMarket();
        vm.stopBroadcast();

        return market;
    }
}
