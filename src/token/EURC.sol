// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EURC is ERC20 {
    constructor() ERC20("EURC", "EURO Coin") {}

    // TODO: Remove this function before deploying to production
    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}