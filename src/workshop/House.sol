// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ERC721 } from "openzeppelin/token/ERC721/ERC721.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";


contract House is ERC721 {

    uint256 public immutable PRICE;
    IERC20 public immutable CURRENCY;

    constructor(address paymentCurrency, uint256 price) ERC721("House", "HOUSE") {
        CURRENCY = IERC20(paymentCurrency);
        PRICE = price;
    }

    function buy(uint256 houseId) external {
        _mint(msg.sender, houseId);
        require(CURRENCY.transferFrom(msg.sender, address(this), PRICE), "House payment failed");
    }

}
