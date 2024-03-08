// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {DeployerEnergyBiddingMarket} from "../script/EnergyBiddingMarket.s.sol";

contract EnergyBiddingMarketTest is Test {
    EnergyBiddingMarket market;

    function setUp() public {
        DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
        market = deployer.run();
    }

    function test_placeBid() public {
    }
}
