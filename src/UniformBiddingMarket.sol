// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniformBiddingMarket {
    IERC20 public eurcToken;

    struct Bid {
        address bidder;
        uint256 amount; // Amount of energy in kWh
        uint256 price; // Price per kWh in EURC.sol
        bool settled; // Flag to indicate if the bid has been settled
    }

    struct Ask {
        address seller;
        uint256 amount; // Amount of energy in kWh
        bool settled; // Flag to indicate if the ask has been settled
    }

    mapping(uint256 => Bid[]) public bidsByHour;
    mapping(uint256 => Ask[]) public asksByHour;
    mapping(uint256 => uint256) public totalAvailableEnergyByHour;
    mapping(uint256 => bool) public isMarketCleared;

    event BidPlaced(address indexed bidder, uint256 hour, uint256 amount, uint256 price);
    event AskPlaced(address indexed seller, uint256 hour, uint256 amount);
    event MarketCleared(uint256 hour, uint256 clearingPrice);
    event SettlementDone(uint256 hour, address user, uint256 amount, bool isBid);

    constructor(address _eurcTokenAddress) {
        eurcToken = IERC20(_eurcTokenAddress);
    }

    function placeBid(uint256 hour, uint256 amount, uint256 price) external {
        // require verify hour correctness
        // Assume the bidder has already approved the contract to spend the necessary amount of EURC.sol
        require(eurcToken.transferFrom(msg.sender, address(this), amount * price), "Transfer failed");
        bidsByHour[hour].push(Bid(msg.sender, amount, price, false));
        emit BidPlaced(msg.sender, hour, amount, price);
    }

    function placeAsk(uint256 hour, uint256 amount) external {
        // require verify hour correctness
        // Assume the seller has already transferred the necessary amount of EURC.sol.sol to cover potential earnings
        // This simplifies the example and focuses on the bidding and settlement process
        asksByHour[hour].push(Ask(msg.sender, amount, false));
        totalAvailableEnergyByHour[hour] += amount;
        emit AskPlaced(msg.sender, hour, amount);
    }

    function clearMarket(uint256 hour) external {
        // todo require the time to be one hour before
        require(bidsByHour[hour].length > 0 && asksByHour[hour].length > 0, "No bids or asks for this hour");
        require(!isMarketCleared[hour], "Market already cleared");

        Bid[] storage bids = bidsByHour[hour];
        sortBids(bids);

        uint256 totalAvailableEnergy = totalAvailableEnergyByHour[hour];
        uint256 totalMatchedEnergy = 0;
        uint256 clearingPrice = determineClearingPrice(hour, totalAvailableEnergy, totalMatchedEnergy);

        for (uint256 i = 0; i < bids.length && totalMatchedEnergy < totalAvailableEnergy; i++) {
            if (!bids[i].settled && bids[i].price >= clearingPrice) {
                uint256 matchedEnergy = bids[i].amount;
                if (totalMatchedEnergy + matchedEnergy > totalAvailableEnergy) {
                    matchedEnergy = totalAvailableEnergy - totalMatchedEnergy;
                }
                totalMatchedEnergy += matchedEnergy;
                // Mark the bid as settled
                bids[i].settled = true;
                emit SettlementDone(hour, bids[i].bidder, matchedEnergy * clearingPrice, true);
            }
        }

        for (uint256 i = 0; i < asksByHour[hour].length; i++) {
            if (!asksByHour[hour][i].settled) {
                asksByHour[hour][i].settled = true;
                emit SettlementDone(hour, asksByHour[hour][i].seller, asksByHour[hour][i].amount * clearingPrice, false);
            }
        }

        require(totalMatchedEnergy > 0, "No matching bids and asks");
        isMarketCleared[hour] = true;
        emit MarketCleared(hour, clearingPrice);
    }

    function sortBids(Bid[] storage bids) internal {
        // Simple insertion sort for demonstration purposes
        for (uint i = 1; i < bids.length; i++) {
            Bid memory key = bids[i];
            uint j = i - 1;
            while ((int(j) >= 0) && (bids[j].price < key.price)) {
                bids[j + 1] = bids[j];
                j--;
            }
            bids[j + 1] = key;
        }
    }

    function determineClearingPrice(uint256 hour, uint256 totalAvailableEnergy, uint256 totalMatchedEnergy) internal view returns (uint256) {
        Bid[] storage bids = bidsByHour[hour];

        // Assuming bids are sorted by price in descending order
        for (uint256 i = 0; i < bids.length; i++) {
            // Simulate the accumulation of bids until the total matched energy equals/exceeds the available energy
            totalMatchedEnergy += bids[i].amount;

            // If the accumulated energy meets/exceeds total available energy, return the current bid's price as the clearing price
            if (totalMatchedEnergy >= totalAvailableEnergy) {
                return bids[i].price;
            }
        }

        // If we cannot find a clearing price that matches or exceeds the total available energy,
        // it indicates a problem with the market setup (not enough bids to cover asks).
        // This should be handled appropriately, perhaps by returning a special value or reverting.
        revert("Cannot determine a clearing price.");
    }


}
