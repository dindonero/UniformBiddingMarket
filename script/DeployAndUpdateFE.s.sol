// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DeployerEnergyBiddingMarket} from "./EnergyBiddingMarket.s.sol";

import {stdJson} from "forge-std/StdJson.sol";

contract DeployAndUpdateFE is Script {
    uint256 constant PROD_CHAIN_ID = 421614;
    uint256 constant NUMBER_OF_REGIONS = 5;
    string constant CONFIG_FILE =
        "../uniform_market_fe/uniform-market-web3modal/constants/addresses.json";
    string constant CLEAR_MARKET_BOT = "../ClearMarketBot/addresses.json";
    string constant TEST_FILE = "./test/addresses.json";

    string[NUMBER_OF_REGIONS] regions = [
        "Portugal",
        "Spain",
        "Germany",
        "Greece",
        "Italy"
    ];

    using stdJson for string;

    function run() public returns (EnergyBiddingMarket[] memory) {
        // Initialize an array to hold the deployed contracts
        EnergyBiddingMarket[] memory markets = new EnergyBiddingMarket[](
            NUMBER_OF_REGIONS
        );
        string memory json;
        string memory tempjson;

        for (uint256 i = 0; i < NUMBER_OF_REGIONS; i++) {
            DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
            EnergyBiddingMarket market = deployer.run();
            markets[i] = market;
            console.log(
                "Deployed EnergyBiddingMarket at address: ",
                address(market)
            );

            // Add the deployed address to the JSON
            tempjson = json.serialize(regions[i], address(market));
        }

        if (block.chainid == PROD_CHAIN_ID) {
            tempjson = tempjson.serialize(vm.toString(block.chainid), tempjson);

            // Write the JSON to the config file

            tempjson.write(CONFIG_FILE);
            tempjson.write(CLEAR_MARKET_BOT);
        } else {
            tempjson.write(TEST_FILE);
        }

        return markets;
    }
}
