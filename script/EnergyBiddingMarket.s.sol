// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";


contract DeployerEnergyBiddingMarket is Script {

    function run() public returns (EnergyBiddingMarket) {
        vm.startBroadcast();

        // Deploy the implementation contract
        EnergyBiddingMarket implementation = new EnergyBiddingMarket();

        // Deploy the proxy contract
        address proxy = UnsafeUpgrades.deployUUPSProxy(address(implementation), abi.encodeWithSignature("initialize(address)", msg.sender));

        vm.stopBroadcast();

        // Cast the proxy to the EnergyBiddingMarket contract
        EnergyBiddingMarket market = EnergyBiddingMarket(address(proxy));

        return (market);
    }
}