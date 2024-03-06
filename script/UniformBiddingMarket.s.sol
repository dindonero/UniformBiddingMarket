// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {UniformBiddingMarket} from "../src/UniformBiddingMarket.sol";
import {EURC} from "../src/token/EURC.sol";

contract DeployerUniformBiddingMarket is Script {

    function run() public returns (UniformBiddingMarket) {
        EURC eurc;
        UniformBiddingMarket market;

        vm.broadcast();
        eurc = new EURC();
        market = new UniformBiddingMarket(address(eurc));
        vm.stopBroadcast();

        return market;
    }
}
