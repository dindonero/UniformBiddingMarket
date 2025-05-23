// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BidSorterLib} from "./lib/BidSorterLib.sol";


    error EnergyBiddingMarket__WrongHourProvided(uint256 hour);
    error EnergyBiddingMarket__WrongHoursProvided(
        uint256 beginHour,
        uint256 endHour
    );
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
    error EnergyBiddingMarket__BidIsAlreadyCanceled(uint256 hour, uint256 index);
    error EnergyBiddingMarket__SellerIsNotWhitelisted(address seller);
    error EnergyBiddingMarket__BidDoesNotExist(uint256 hour, uint256 index);

contract EnergyBiddingMarket is UUPSUpgradeable, OwnableUpgradeable {

    struct Bid {
        address bidder;
        bool settled; // Flag to indicate if the bid has been settled
        bool canceled; // Flag to indicate if the bid has been canceled
        uint256 amount; // Amount of energy in kWh
        uint256 price; // Price per kWh in EURC.sol
    }

    struct Ask {
        address seller;
        bool settled; // Flag to indicate if the ask has been settled
        bool canceled; // Flag to indicate if the ask has been canceled
        uint256 amount; // Amount of energy in kWh
        uint256 matchedAmount; // Amount of energy in kWh that has been matched
    }

    uint256 public constant MIN_PRICE = 1000000000000; // 0.000001 ETH per kwH, averaged at $0.003 USD expected to increase

    mapping(uint256 => mapping(uint256 => Bid)) public bidsByHour;
    mapping(uint256 => mapping(uint256 => Ask)) public asksByHour;

    mapping(uint256 => uint256) public totalBidsByHour;
    mapping(uint256 => uint256) public totalAsksByHour;

    mapping(uint256 => uint256) public clearingPricePerHour;

    mapping(uint256 => uint256) internal totalAvailableEnergyByHour;
    mapping(uint256 => bool) public isMarketCleared;

    mapping(address => uint256) public claimableBalance;

    mapping(address => bool) public s_whitelistedSellers;

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

    modifier whitelistedSeller(address seller) {
        if (!s_whitelistedSellers[seller])
            revert EnergyBiddingMarket__SellerIsNotWhitelisted(seller);
        _;
    }

    modifier isMarketNotCleared(uint256 hour) {
        if (isMarketCleared[hour])
            revert EnergyBiddingMarket__MarketAlreadyClearedForThisHour(hour);
        _;
    }

    /* ///////////////////// */
    /*                       */
    /* UUPSUpgradeable logic */
    /*                       */
    /* ///////////////////// */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Places a bid for energy in a specific market hour.
    /// @dev Requires that the bid price is above the minimum price and the bid amount is not zero.
    ///      Bids can only be placed for future hours not yet cleared.
    /// @param hour The market hour for which the bid is being placed.
    function placeBid(
        uint256 hour,
        uint256 amount
    ) external payable {
        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();

        uint256 price = msg.value / amount;
        uint256 totalCost = price * amount;
        uint256 excess = msg.value - totalCost;
        _placeBid(hour, amount, price);

        if (excess > 0) {
            (bool success,) = msg.sender.call{value: excess}("");
            require(success, "It tranfer failed");
        }
    }

    /// @notice Places an ask for selling energy in a specific market hour.
    /// @dev Requires that the ask amount is not zero and can only be placed for future hours not yet cleared.
    /// @param amount The amount of energy in kWh being offered.
    /// @param inBehalfOf The address correspondent to the entity that sold the energy.
    function placeAsk(
        uint256 amount,
        address inBehalfOf
    ) external /*whitelistedSeller(msg.sender)*/ { // todo remove comment
        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();

        uint256 hour = getCurrentHourTimestamp();

        uint256 totalAsks = totalAsksByHour[hour];

        asksByHour[hour][totalAsks] = (Ask(inBehalfOf, false, false, amount, 0));
        totalAsksByHour[hour]++;
        totalAvailableEnergyByHour[hour] += amount;
        emit AskPlaced(inBehalfOf, hour, amount);
    }

    /// @notice Places multiple bids for energy over a range of market hours.
    /// @dev Calls `placeBid` for each hour in the specified range.
    /// @param beginHour The starting hour of the range.
    /// @param endHour The ending hour of the range.
    /// @param amount The amount of energy in kWh being bid for each hour.
    function placeMultipleBids(
        uint256 beginHour,
        uint256 endHour,
        uint256 amount
    ) external payable {
        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();

        if (beginHour + 3600 > endHour)
            revert EnergyBiddingMarket__WrongHoursProvided(beginHour, endHour);

        uint256 totalEnergy = ((amount * (endHour - beginHour)) / 3600);
        uint256 price = msg.value / totalEnergy;
        uint256 totalCost = price * totalEnergy;
        uint256 excess = msg.value - totalCost;

        for (uint256 i = beginHour; i < endHour; i += 3600) {
            _placeBid(i, amount, price);
        }

        if (excess > 0) {
            (bool success,) = msg.sender.call{value: excess}("");
            require(success, "ETH transfer failed");
        }
    }

    /// @notice Places multiple bids for energy in specified market hours.
    /// @dev Calls `_placeBid` for each hour in the provided array of hours.
    /// @param biddingHours An array of market hours for which bids are being placed.
    /// @param amount The amount of energy in kWh being bid for each hour.
    function placeMultipleBids(
        uint256[] memory biddingHours,
        uint256 amount
    ) external payable {
        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();

        uint256 bidsAmount = biddingHours.length;

        uint256 totalEnergy = amount * bidsAmount;
        uint256 price = msg.value / totalEnergy;
        uint256 totalCost = price * totalEnergy;
        uint256 excess = msg.value - totalCost;
        for (uint256 i = 0; i < bidsAmount; i++) {
            _placeBid(biddingHours[i], amount, price);
        }

        if (excess > 0) {
            (bool success,) = msg.sender.call{value: excess}("");
            require(success, "ETH transfer failed");
        }
    }

    /// @notice Allows users to claim any balance available to them from fulfilled bids or asks.
    /// @dev Reverts if the user has no claimable balance.
    function claimBalance() external {
        uint256 balance = claimableBalance[msg.sender];
        if (balance == 0)
            revert EnergyBiddingMarket__NoClaimableBalance(msg.sender);
        claimableBalance[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "ETH transfer failed");
    }

    /// @notice Clears the market for a specific hour, matching bids and asks based on the determined clearing price.
    /// @dev This function matches orders in price descending order and settles them. Can only be called 1 hour after the market hour.
    ///      Anyone can call this function to clear the market. However, the system does not currently reimburse the caller for gas expenses.
    ///      It is assumed that the market will either be operated by an entity that requires its operation, or the gas costs will be shared among the participants of the market.
    /// @param hour The market hour to clear.
    function clearMarket(uint256 hour) external assertExactHour(hour) {
        if (hour + 3600 > block.timestamp)
            revert EnergyBiddingMarket__WrongHourProvided(hour);
        _clearMarket(hour);
    }

    /// @notice Clears the market for the past hour, matching bids and asks based on the determined clearing price.
    function clearMarketPastHour() external {
        uint256 hour = getCurrentHourTimestamp() - 3600;
        _clearMarket(hour);
    }

    /// @notice Allows a bidder to cancel their bid for a specific hour if the market has not yet been cleared.
    /// @dev Only the owner of the bid can cancel it, and it cannot be cancelled once the market is cleared.
    /// @param hour The hour of the bid to cancel.
    /// @param index The index of the bid in the storage array.
    function cancelBid(uint256 hour, uint256 index) external isMarketNotCleared(hour) {
        if (index >= totalBidsByHour[hour]) {
            revert EnergyBiddingMarket__BidDoesNotExist(hour, index);
        }
        if (msg.sender != bidsByHour[hour][index].bidder)
            revert EnergyBiddingMarket__OnlyBidOwnerCanCancel(hour, msg.sender);
        Bid storage bid = bidsByHour[hour][index];
        if (bid.canceled)
            revert EnergyBiddingMarket__BidIsAlreadyCanceled(hour, index);
        bid.canceled = true;
        claimableBalance[msg.sender] += bid.amount * bid.price;
    }

    function whitelistSeller(address seller, bool enable) external onlyOwner {
        require(seller != address(0), "Invalid seller address");
        s_whitelistedSellers[seller] = enable;
    }

    /// @notice Places a bid for energy in a specific market hour.
    /// @dev Requires that the bid price is above the minimum price and the bid amount is not zero.
    ///      Bids can only be placed for future hours not yet cleared.
    /// @param hour The market hour for which the bid is being placed.
    /// @param amount The amount of energy in kWh being bid for.
    /// @param price The price per kWh in EURC.
    function _placeBid(
        uint256 hour,
        uint256 amount,
        uint256 price
    ) internal assertExactHour(hour) isMarketNotCleared(hour) {
        if (hour <= block.timestamp)
            revert EnergyBiddingMarket__WrongHourProvided(hour);

        if (price < MIN_PRICE)
            revert EnergyBiddingMarket__BidMinimumPriceNotMet(price, MIN_PRICE);

        uint256 totalBids = totalBidsByHour[hour];

        bidsByHour[hour][totalBids] = (Bid(msg.sender, false, false, amount, price));
        totalBidsByHour[hour]++;
        emit BidPlaced(msg.sender, hour, amount, price);
    }

    /// @notice Returns the claimable balance of a user.
    /// @dev This balance includes any funds due to the user from market operations, such as fulfilled bids or asks.
    /// @param user The address of the user whose balance is being queried.
    /// @return The claimable balance of the user.
    function balanceOf(address user) external view returns (uint256) {
        return claimableBalance[user];
    }

    function _clearMarket(uint256 hour) internal isMarketNotCleared(hour) {

        Bid[] memory bids = getBidsByHour(hour);
        uint[] memory sortedIndices = BidSorterLib.sortedBidIndicesDescending(bids);

        if (sortedIndices.length == 0)
            revert EnergyBiddingMarket__NoBidsOrAsksForThisHour(hour);

        uint256 totalEnergyAvailable = totalAvailableEnergyByHour[hour];
        uint256 totalMatchedEnergy;

        uint256 clearingPrice = determineClearingPrice(hour, bids, sortedIndices);
        clearingPricePerHour[hour] = clearingPrice;

        uint256 fulfilledAsks = 0;

        for (uint256 i = 0; i < sortedIndices.length; i++) {
            Bid storage bid = bidsByHour[hour][sortedIndices[i]];
            if (bid.amount > totalEnergyAvailable - totalMatchedEnergy || clearingPrice == 0) {
                // if this consumes too much gas, change it to cancel bids
                for (uint k = i; k < sortedIndices.length; k++)
                    claimableBalance[bidsByHour[hour][sortedIndices[k]].bidder] +=
                        bidsByHour[hour][sortedIndices[k]].amount *
                        bidsByHour[hour][sortedIndices[k]].price;
                break;
            }

            uint256 totalMatchedEnergyForBid = 0;

            for (uint256 j = fulfilledAsks; j < totalAsksByHour[hour]; j++) {
                // todo: gas opt - make ask in memory outside of bid loop for improvement when lots of bids for big asks
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

            totalMatchedEnergy += bid.amount;
        }

        isMarketCleared[hour] = true;
        emit MarketCleared(hour, clearingPrice);
    }

    /// @dev Determines the clearing price for a specific hour based on bid amounts and available energy.
    /// @param hour The hour for which to determine the clearing price.
    /// @return The clearing price based on bid competition and energy availability.
    function determineClearingPrice(
        uint256 hour,
        Bid[] memory bids,
        uint[] memory sortedIndices
    ) internal view returns (uint256) {
        uint256 totalBids = sortedIndices.length;

        uint256 totalMatchedEnergy = 0;
        uint256 totalAvailableEnergy = totalAvailableEnergyByHour[hour];

        // Assuming bids are sorted by price in descending order
        for (uint256 i = 0; i < totalBids; i++) {
            // Simulate the accumulation of bids until the total matched energy equals/exceeds the available energy
            totalMatchedEnergy += bids[sortedIndices[i]].amount;

            // If the accumulated energy meets/exceeds total available energy, return the last bid's price as the clearing price
            // todo check with ian: we return the last bid price so that there is no half matched bid
            if (totalMatchedEnergy > totalAvailableEnergy) {
                if (i == 0) return 0;
                else return bids[sortedIndices[i - 1]].price;
            }
        }

        // If we cannot find a clearing price that matches or exceeds the total available energy,
        // todo check with ian: we return the last bid price
        return bidsByHour[hour][sortedIndices[totalBids - 1]].price;
    }

    /// @notice Retrieves the Unix timestamp of the beginning of the current hour.
    /// @dev This function rounds down the current block timestamp to the nearest hour.
    ///      The calculation is performed by dividing the current timestamp by 3600 (seconds per hour)
    ///      and then multiplying by 3600 to remove any minutes and seconds.
    /// @return The Unix timestamp corresponding to the start of the current hour.
    function getCurrentHourTimestamp() public view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;
        return (currentTimestamp / 3600) * 3600;
    }

    /// @notice Retrieves all bids placed for a specific hour.
    /// @param hour The hour for which bids are being retrieved.
    /// @return An array of Bid structs for the specified hour.
    function getBidsByHour(uint256 hour) public view returns (Bid[] memory) {
        uint256 totalBids = totalBidsByHour[hour];
        Bid[] memory bids = new Bid[](totalBids);

        for (uint256 i = 0; i < totalBids; i++) {
            bids[i] = bidsByHour[hour][i];
        }

        return bids;
    }

    /// @notice Retrieves all asks placed for a specific hour.
    /// @param hour The hour for which asks are being retrieved.
    /// @return An array of Ask structs for the specified hour.
    function getAsksByHour(uint256 hour) external view returns (Ask[] memory) {
        uint256 totalAsks = totalAsksByHour[hour];
        Ask[] memory asks = new Ask[](totalAsks);

        for (uint256 i = 0; i < totalAsks; i++) {
            asks[i] = asksByHour[hour][i];
        }

        return asks;
    }

    /// @notice Retrieves all bids placed by a specific user for a specific hour.
    /// @param hour The hour for which bids are being retrieved.
    /// @param user The address of the user whose bids are being retrieved.
    /// @return An array of Bid structs that were placed by the specified user for the specified hour.
    function getBidsByAddress(
        uint256 hour,
        address user
    ) external view returns (Bid[] memory) {
        uint256 totalBids = totalBidsByHour[hour];
        uint256 count = 0;
        for (uint256 i = 0; i < totalBids; i++) {
            if (bidsByHour[hour][i].bidder == user) count++;
        }
        Bid[] memory userBids = new Bid[](count);
        count = 0;
        for (uint256 i = 0; i < totalBids; i++) {
            if (bidsByHour[hour][i].bidder == user) {
                userBids[count] = bidsByHour[hour][i];
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
        uint256 totalAsks = totalAsksByHour[hour];
        uint256 count = 0;
        for (uint256 i = 0; i < totalAsks; i++) {
            if (asksByHour[hour][i].seller == user) {
                count++;
            }
        }

        Ask[] memory userAsks = new Ask[](count);
        count = 0;
        for (uint256 i = 0; i < totalAsks; i++) {
            if (asksByHour[hour][i].seller == user) {
                userAsks[count] = asksByHour[hour][i];
                count++;
            }
        }
        return userAsks;
    }

    /// @notice Retrieves the clearing price for a specific hour.
    /// @param hour The hour for which the clearing price is being retrieved.
    /// @return The clearing price for the specified hour.
    function getClearingPrice(uint256 hour) external view returns (uint256) {
        return clearingPricePerHour[hour];
    }
}
