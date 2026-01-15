// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";

contract MockStrategy is IStrategy {
    IERC20 public immutable token;

    constructor(address asset_) {
        token = IERC20(asset_);
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function totalAssets() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function deposit(
        uint256 /*assets*/
    )
        external {
        // assets already transferred in; no-op
    }

    function withdraw(uint256 assets, address recipient) external returns (uint256 withdrawn) {
        uint256 bal = token.balanceOf(address(this));
        withdrawn = assets <= bal ? assets : bal;
        if (withdrawn > 0) {
            token.transfer(recipient, withdrawn);
        }
    }
}
