// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console} from "forge-std/Test.sol";

error EnergyBiddingMarket__WrongHourProvided(uint256 hour);
error EnergyBiddingMarket__NoBidsOrAsksForThisHour(uint256 hour);
error EnergyBiddingMarket__MarketAlreadyClearedForThisHour(uint256 hour);
error EnergyBiddingMarket__NoClaimableBalance(address user);
error EnergyBiddingMarket__OnlyAskOwnerCanCancel(uint256 hour, address seller);
error EnergyBiddingMarket__OnlyBidOwnerCanCancel(uint256 hour, address bidder);
error EnergyBiddingMarket__NoBidFulfilled(uint256 hour);
error EnergyBiddingMarket__BidMinimumPriceNotMet(
    uint256 price,
    uint256 minimumPrice
);
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

    event BidPlaced(
        address indexed bidder,
        uint256 hour,
        uint256 amount,
        uint256 price
    );
    event AskPlaced(address indexed seller, uint256 hour, uint256 amount);

    event BidFulfilled(
        uint256 indexed hour,
        uint256 indexed id,
        address indexed bidder,
        uint256 amount,
        uint256 price
    );
    event AskFulfilled(
        uint256 indexed hour,
        address indexed seller,
        uint256 indexed id,
        uint256 amount,
        uint256 price
    );
    event AskPartiallyFulfilled(
        uint256 indexed hour,
        address indexed seller,
        uint256 indexed id,
        uint256 amount,
        uint256 price
    );

    event MarketCleared(uint256 hour, uint256 clearingPrice);
    event SettlementDone(
        uint256 hour,
        address user,
        uint256 amount,
        bool isBid
    );

    modifier assertExactHour(uint256 hour) {
        if (hour % 3600 != 0)
            revert EnergyBiddingMarket__WrongHourProvided(hour);
        _;
    }

    /// @notice Constructs the EnergyBiddingMarket contract.
    /// @param _eurcTokenAddress The address of the EURC token contract used for bidding and settlements.
    constructor(address _eurcTokenAddress) {
        EURC = IERC20(_eurcTokenAddress);
    }

    /// @notice Places a bid for energy in a specific market hour.
    /// @dev Requires that the bid price is above the minimum price and the bid amount is not zero.
    ///      Bids can only be placed for future hours not yet cleared.
    /// @param hour The market hour for which the bid is being placed.
    /// @param amount The amount of energy in kWh being bid for.
    /// @param price The price per kWh in EURC.
    function placeBid(
        uint256 hour,
        uint256 amount,
        uint256 price
    ) public assertExactHour(hour) {
        if (hour <= block.timestamp)
            revert EnergyBiddingMarket__WrongHourProvided(hour);

        if (price < MIN_PRICE)
            revert EnergyBiddingMarket__BidMinimumPriceNotMet(price, MIN_PRICE);

        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();

        if (isMarketCleared[hour])
            revert EnergyBiddingMarket__MarketAlreadyClearedForThisHour(hour);

        // Assume the bidder has already approved the contract to spend the necessary amount of EURC.sol
        EURC.safeTransferFrom(msg.sender, address(this), amount * price);
        bidsByHour[hour].push(Bid(msg.sender, amount, price, false));
        emit BidPlaced(msg.sender, hour, amount, price);
    }

    /// @notice Places an ask for selling energy in a specific market hour.
    /// @dev Requires that the ask amount is not zero and can only be placed for future hours not yet cleared.
    /// @param hour The market hour for which the ask is being placed.
    /// @param amount The amount of energy in kWh being offered.
    function placeAsk(
        uint256 hour,
        uint256 amount
    ) public assertExactHour(hour) {
        if (hour >= block.timestamp || hour + 3600 <= block.timestamp)
            revert EnergyBiddingMarket__WrongHourProvided(hour);

        if (isMarketCleared[hour])
            revert EnergyBiddingMarket__MarketAlreadyClearedForThisHour(hour);

        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();

        asksByHour[hour].push(Ask(msg.sender, amount, 0, false));
        totalAvailableEnergyByHour[hour] += amount;
        emit AskPlaced(msg.sender, hour, amount);
    }

    /// @notice Places multiple bids for energy over a range of market hours.
    /// @dev Calls `placeBid` for each hour in the specified range.
    /// @param beginHour The starting hour of the range.
    /// @param endHour The ending hour of the range.
    /// @param amount The amount of energy in kWh being bid for each hour.
    /// @param price The price per kWh in EURC for each bid.
    function placeMultipleBids(
        uint256 beginHour,
        uint256 endHour,
        uint256 amount,
        uint256 price
    ) external {
        for (uint256 i = beginHour; i < endHour; i += 3600) {
            placeBid(i, amount, price);
        }
    }

    /// @notice Allows users to claim any balance available to them from fulfilled bids or asks.
    /// @dev Reverts if the user has no claimable balance.
    function claimBalance() external {
        uint256 balance = claimableBalance[msg.sender];
        if (balance == 0)
            revert EnergyBiddingMarket__NoClaimableBalance(msg.sender);
        claimableBalance[msg.sender] = 0;
        EURC.safeTransfer(msg.sender, balance);
    }

    /// @notice Clears the market for a specific hour, matching bids and asks based on the determined clearing price.
    /// @dev This function matches orders in price descending order and settles them. Can only be called 1 hour after the market hour.
    ///      Anyone can call this function to clear the market. However, the system does not currently reimburse the caller for gas expenses.
    ///      It is assumed that the market will either be operated by an entity that requires its operation, or the gas costs will be shared among the participants of the market.
    /// @param hour The market hour to clear.
    function clearMarket(uint256 hour) external assertExactHour(hour) {
        if (hour + 3600 > block.timestamp)
            revert EnergyBiddingMarket__WrongHourProvided(hour);
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
            if (bid.price < clearingPrice)
                // unfulfilled bid orders
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
                    claimableBalance[ask.seller] +=
                        amountLeftInAsk *
                        clearingPrice;
                    emit AskFulfilled(
                        hour,
                        ask.seller,
                        j,
                        amountLeftInAsk,
                        clearingPrice
                    );
                    fulfilledAsks++;
                    if (totalMatchedEnergyForBid == bid.amount)
                        // saves 1 iteration
                        break;
                } else {
                    ask.matchedAmount += bid.amount - totalMatchedEnergyForBid;
                    //handle ask is partially fulfilled
                    claimableBalance[ask.seller] +=
                        (bid.amount - totalMatchedEnergyForBid) *
                        clearingPrice;
                    emit AskPartiallyFulfilled(
                        hour,
                        ask.seller,
                        j,
                        ask.amount,
                        clearingPrice
                    );
                    break;
                }
            }

            // handle Bid is settled
            // bid is always fulfilled, since it only runs when bid is above the clearing price
            bid.settled = true;
            // refund the remaining amount of the bid
            claimableBalance[bid.bidder] +=
                bid.amount *
                (bid.price - clearingPrice);
            emit BidFulfilled(hour, i, bid.bidder, bid.amount, clearingPrice);
        }

        isMarketCleared[hour] = true;
        emit MarketCleared(hour, clearingPrice);
    }

    /* todo change bids from list to mapping or add cancel bool to bid
    /// @notice Allows a bidder to cancel their bid for a specific hour if the market has not yet been cleared.
    /// @dev Only the owner of the bid can cancel it, and it cannot be cancelled once the market is cleared.
    /// @param hour The hour of the bid to cancel.
    /// @param index The index of the bid in the storage array.
    function cancelBid(uint256 hour, uint256 index) external {
        if (msg.sender != bidsByHour[hour][index].bidder)
            revert EnergyBiddingMarket__OnlyBidOwnerCanCancel(hour, msg.sender);
        if (isMarketCleared[hour])
            revert EnergyBiddingMarket__MarketAlreadyClearedForThisHour(hour);
        EURC.safeTransfer(msg.sender, bidsByHour[hour][index].amount * bidsByHour[hour][index].price);
        bidsByHour[hour][index] = bidsByHour[hour][bidsByHour[hour].length - 1];
        bidsByHour[hour].pop();
    }*/

    /// @notice Returns the claimable balance of a user.
    /// @dev This balance includes any funds due to the user from market operations, such as fulfilled bids or asks.
    /// @param user The address of the user whose balance is being queried.
    /// @return The claimable balance of the user.
    function balanceOf(address user) external view returns (uint256) {
        return claimableBalance[user];
    }

    /// @dev Sorts an array of bids in descending order by price. This is used internally to prepare for market clearing.
    /// @param bids The array of Bid structs to sort.
    function sortBids(Bid[] storage bids) internal {
        for (uint i = 1; i < bids.length; i++) {
            Bid memory key = bids[i];
            uint j = i;
            while (j > 0 && bids[j - 1].price < key.price) {
                bids[j] = bids[j - 1];
                j--;
            }
            if (j != i) {
                bids[j] = key;
            }
        }
    }

    /// @dev Determines the clearing price for a specific hour based on bid amounts and available energy.
    /// @param hour The hour for which to determine the clearing price.
    /// @return The clearing price based on bid competition and energy availability.
    function determineClearingPrice(
        uint256 hour
    ) internal view returns (uint256) {
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
                if (i == 0) revert EnergyBiddingMarket__NoBidFulfilled(hour);
                else return bids[i - 1].price;
            }
        }

        // If we cannot find a clearing price that matches or exceeds the total available energy,
        // todo check with ian: we return the last bid price
        return bids[bids.length - 1].price;
    }

    /// @notice Retrieves all bids placed for a specific hour.
    /// @param hour The hour for which bids are being retrieved.
    /// @return An array of Bid structs for the specified hour.
    function getBidsByHour(uint256 hour) external view returns (Bid[] memory) {
        return bidsByHour[hour];
    }

    /// @notice Retrieves all asks placed for a specific hour.
    /// @param hour The hour for which asks are being retrieved.
    /// @return An array of Ask structs for the specified hour.
    function getAsksByHour(uint256 hour) external view returns (Ask[] memory) {
        return asksByHour[hour];
    }

    /// @notice Retrieves all bids placed by a specific user for a specific hour.
    /// @param hour The hour for which bids are being retrieved.
    /// @param user The address of the user whose bids are being retrieved.
    /// @return An array of Bid structs that were placed by the specified user for the specified hour.
    function getBidsByAddress(
        uint256 hour,
        address user
    ) external view returns (Bid[] memory) {
        Bid[] memory bids = bidsByHour[hour];
        uint256 count = 0;
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].bidder == user) count++;
        }
        Bid[] memory userBids = new Bid[](count);
        count = 0;
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].bidder == user) {
                userBids[count] = bids[i];
                count++;
            }
        }
        return userBids;
    }

    /// @notice Retrieves all asks placed by a specific user for a specific hour.
    /// @param hour The hour for which asks are being retrieved.
    /// @param user The address of the user whose asks are being retrieved.
    /// @return An array of Ask structs that were placed by the specified user for the specified hour.
    function getAsksByAddress(
        uint256 hour,
        address user
    ) external view returns (Ask[] memory) {
        Ask[] memory asks = asksByHour[hour];
        uint256 count = 0;
        for (uint256 i = 0; i < asks.length; i++) {
            if (asks[i].seller == user) {
                count++;
            }
        }

        Ask[] memory userAsks = new Ask[](count);
        count = 0;
        for (uint256 i = 0; i < asks.length; i++) {
            if (asks[i].seller == user) {
                userAsks[count] = asks[i];
                count++;
            }
        }
        return userAsks;
    }
}
