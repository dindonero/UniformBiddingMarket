// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";


contract DeployerEnergyBiddingMarket is Script {

    function run() public returns (EnergyBiddingMarket) {

        uint256 hour = (block.timestamp / 3600) * 3600;
        console.log(hour);

        EnergyBiddingMarket market = EnergyBiddingMarket(0x2A9510Ae0aD44955b5749b3b9f31707F8D459529);

        vm.startBroadcast();

        // Deploy the implementation contract

        // Deploy the proxy contract
        //address proxy = UnsafeUpgrades.deployUUPSProxy(address(implementation), abi.encodeWithSignature("initialize(address)", msg.sender));

        //EnergyBiddingMarket market = EnergyBiddingMarket(address(proxy));

        //market.placeAsk(hour, 199);
        vm.stopBroadcast();

        // Cast the proxy to the EnergyBiddingMarket contract

        return (market);
    }
}