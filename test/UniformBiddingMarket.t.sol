// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {UniformBiddingMarket} from "../src/UniformBiddingMarket.sol";
import {DeployerUniformBiddingMarket} from "../script/UniformBiddingMarket.s.sol";

contract UniformBiddingMarketTest is Test {
    UniformBiddingMarket market;

    function setUp() public {
        DeployerUniformBiddingMarket deployer = new DeployerUniformBiddingMarket();
        market = deployer.run();
    }
}
