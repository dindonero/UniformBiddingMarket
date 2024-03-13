// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error EnergyBiddingMarket__WrongHourProvided(uint256 hour);
error EnergyBiddingMarket__NoBidsOrAsksForThisHour(uint256 hour);
error EnergyBiddingMarket__MarketAlreadyClearedForThisHour(uint256 hour);
error EnergyBiddingMarket__NoClaimableBalance(address user);
error EnergyBiddingMarket__OnlyAskOwnerCanCancel(uint256 hour, address seller);
error EnergyBiddingMarket__OnlyBidOwnerCanCancel(uint256 hour, address bidder);
error EnergyBiddingMarket__NoBidFulfilled(uint256 hour);
error EnergyBiddingMarket__BidMinimumPriceNotMet(uint256 price, uint256 minimumPrice);
error EnergyBiddingMarket__AmountCannotBeZero();

contract EnergyBiddingMarket {
    using SafeERC20 for IERC20;

    IERC20 public EURC;

    struct Bid {
        address bidder;
        uint256 amount; // Amount of energy in kWh
        uint256 price; // Price per kWh in EURC.sol
        bool settled; // Flag to indicate if the bid has been settled
    }

    struct Ask {
        address seller;
        uint256 amount; // Amount of energy in kWh
        uint256 matchedAmount; // Amount of energy in kWh that has been matched
        bool settled; // Flag to indicate if the ask has been settled
    }

    uint8 public constant PRICE_DECIMALS = 6; // same as EURC decimals
    uint256 public constant MIN_PRICE = 10000; // 0.01 EURC per kwH

    //todo change structure to mapping(uint256 => mapping(uint256 => Bid)) for gas optimization and clear cancel option
    mapping(uint256 => Bid[]) public bidsByHour;
    mapping(uint256 => Ask[]) public asksByHour;
    mapping(uint256 => uint256) internal totalAvailableEnergyByHour;
    mapping(uint256 => bool) public isMarketCleared;

    mapping(address => uint256) public claimableBalance;

    event BidPlaced(address indexed bidder, uint256 hour, uint256 amount, uint256 price);
    event AskPlaced(address indexed seller, uint256 hour, uint256 amount);

    event BidFulfilled(uint256 indexed hour, uint256 indexed id, address indexed bidder, uint256 amount, uint256 price);
    event AskFulfilled(uint256 indexed hour, address indexed seller, uint256 indexed id, uint256 amount, uint256 price);
    event AskPartiallyFulfilled(uint256 indexed hour, address indexed seller, uint256 indexed id, uint256 amount, uint256 price);

    event MarketCleared(uint256 hour, uint256 clearingPrice);
    event SettlementDone(uint256 hour, address user, uint256 amount, bool isBid);

    constructor(address _eurcTokenAddress) {
        EURC = IERC20(_eurcTokenAddress);
    }

    function placeBid(uint256 hour, uint256 amount, uint256 price) external {
        if (hour % 3600 != 0 || hour <= block.timestamp)
            revert EnergyBiddingMarket__WrongHourProvided(hour);

        if (price < MIN_PRICE)
            revert EnergyBiddingMarket__BidMinimumPriceNotMet(price, MIN_PRICE);

        if (amount == 0)
            revert EnergyBiddingMarket__AmountCannotBeZero();

        if (isMarketCleared[hour])
            revert EnergyBiddingMarket__MarketAlreadyClearedForThisHour(hour);

        // Assume the bidder has already approved the contract to spend the necessary amount of EURC.sol
        EURC.safeTransferFrom(msg.sender, address(this), amount * price);
        bidsByHour[hour].push(Bid(msg.sender, amount, price, false));
        emit BidPlaced(msg.sender, hour, amount, price);
    }

    function placeAsk(uint256 hour, uint256 amount) external {
        if (hour % 3600 != 0 || hour <= block.timestamp)
            revert EnergyBiddingMarket__WrongHourProvided(hour);

        if (isMarketCleared[hour])
            revert EnergyBiddingMarket__MarketAlreadyClearedForThisHour(hour);

        if (amount == 0)
            revert EnergyBiddingMarket__AmountCannotBeZero();

        asksByHour[hour].push(Ask(msg.sender, amount, 0, false));
        totalAvailableEnergyByHour[hour] += amount;
        emit AskPlaced(msg.sender, hour, amount);
    }

    function claimBalance() external {
        uint256 balance = claimableBalance[msg.sender];
        if (balance == 0)
            revert EnergyBiddingMarket__NoClaimableBalance(msg.sender);
        claimableBalance[msg.sender] = 0;
        EURC.safeTransfer(msg.sender, balance);
    }

    function clearMarket(uint256 hour) external {
        // todo require the time to be one hour before
        if (bidsByHour[hour].length == 0 || asksByHour[hour].length == 0)
            revert EnergyBiddingMarket__NoBidsOrAsksForThisHour(hour);
        if (isMarketCleared[hour])
            revert EnergyBiddingMarket__MarketAlreadyClearedForThisHour(hour);

        Bid[] storage bids = bidsByHour[hour];
        sortBids(bids);

        uint256 clearingPrice = determineClearingPrice(hour);

        uint256 fulfilledAsks = 0;

        for (uint256 i = 0; i < bids.length; i++) {
            Bid storage bid = bids[i];
            if (bid.price < clearingPrice) // unfulfilled bid orders
                break;

            uint256 totalMatchedEnergyForBid = 0;

            for (uint256 j = fulfilledAsks; j < asksByHour[hour].length; j++) {
                Ask storage ask = asksByHour[hour][j];
                uint256 amountLeftInAsk = ask.amount - ask.matchedAmount;
                if (totalMatchedEnergyForBid + amountLeftInAsk <= bid.amount) {
                    ask.settled = true;
                    ask.matchedAmount = ask.amount;
                    totalMatchedEnergyForBid += amountLeftInAsk;
                    // handle ask is fulfilled
                    claimableBalance[ask.seller] += amountLeftInAsk * clearingPrice;
                    emit AskFulfilled(hour, ask.seller, j, amountLeftInAsk, clearingPrice);
                    fulfilledAsks++;
                    if (totalMatchedEnergyForBid + amountLeftInAsk == bid.amount)
                        break;
                } else {
                    ask.matchedAmount += bid.amount - totalMatchedEnergyForBid;
                    //handle ask is partially fulfilled
                    claimableBalance[ask.seller] += (bid.amount - totalMatchedEnergyForBid) * clearingPrice;
                    emit AskPartiallyFulfilled(hour, ask.seller, j, ask.amount, clearingPrice);
                    break;
                }
            }

            // handle Bid is settled
            bid.settled = true;
            // refund the remaining amount of the bid
            claimableBalance[bid.bidder] += bid.amount * (bid.price - clearingPrice);
            emit BidFulfilled(hour, i, bid.bidder, bid.amount, clearingPrice);
        }

        isMarketCleared[hour] = true;
        emit MarketCleared(hour, clearingPrice);
    }

    /* todo change bids from list to mapping or add cancel bool to bid
    function cancelBid(uint256 hour, uint256 index) external {
        if (msg.sender != bidsByHour[hour][index].bidder)
            revert EnergyBiddingMarket__OnlyBidOwnerCanCancel(hour, msg.sender);
        if (isMarketCleared[hour])
            revert EnergyBiddingMarket__MarketAlreadyClearedForThisHour(hour);
        EURC.safeTransfer(msg.sender, bidsByHour[hour][index].amount * bidsByHour[hour][index].price);
        bidsByHour[hour][index] = bidsByHour[hour][bidsByHour[hour].length - 1];
        bidsByHour[hour].pop();
    }*/

    function balanceOf(address user) external view returns (uint256) {
        return claimableBalance[user];
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

    function determineClearingPrice(uint256 hour) internal view returns (uint256) {
        Bid[] memory bids = bidsByHour[hour];

        uint256 totalMatchedEnergy = 0;
        uint256 totalAvailableEnergy = totalAvailableEnergyByHour[hour];

        // Assuming bids are sorted by price in descending order
        for (uint256 i = 0; i < bids.length; i++) {
            // Simulate the accumulation of bids until the total matched energy equals/exceeds the available energy
            totalMatchedEnergy += bids[i].amount;

            // If the accumulated energy meets/exceeds total available energy, return the last bid's price as the clearing price
            // todo check with ian: we return the last bid price so that there is no half matched bid
            if (totalMatchedEnergy >= totalAvailableEnergy) {
                if (i == 0)
                    revert EnergyBiddingMarket__NoBidFulfilled(hour);
                else
                    return bids[i - 1].price;
            }
        }

        // If we cannot find a clearing price that matches or exceeds the total available energy,
        // todo check with ian: we return the last bid price
        return bids[bids.length - 1].price;
    }


}
