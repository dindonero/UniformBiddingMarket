// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {EURC} from "../src/token/EURC.sol";

contract DeployerEnergyBiddingMarket is Script {

    function run() public returns (EnergyBiddingMarket) {
        EURC eurc;
        EnergyBiddingMarket market;

        vm.startBroadcast();
        eurc = new EURC();
        market = new EnergyBiddingMarket(address(eurc));
        vm.stopBroadcast();

        return market;
    }
}
