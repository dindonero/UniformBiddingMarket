// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/*
 * @dev for deploying with proxy in orbit use:
 * forge script ./script/EnergyBiddingMarket.s.sol --private-key ${PRIVATE_KEY} --rpc-url https://wattswap.novaims.unl.pt:8443 --broadcast --slow --gas-estimate-multiplier 200000
*/
contract DeployerEnergyBiddingMarket is Script {

    function run() public returns (EnergyBiddingMarket) {
        vm.startBroadcast();

        // Deploy the proxy contract
        address proxy = Upgrades.deployUUPSProxy(
            "EnergyBiddingMarket.sol:EnergyBiddingMarket",
            abi.encodeWithSignature("initialize(address)", msg.sender)
        );

        console.logAddress(proxy);
        vm.stopBroadcast();

        // Cast the proxy to the EnergyBiddingMarket contract
        EnergyBiddingMarket market = EnergyBiddingMarket(address(proxy));

        return (market);
    }
}