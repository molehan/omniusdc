// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";

contract StrategyManager is AccessControl, IStrategyManager {
    error ZeroAddress();
    error OnlyVault();
    error StrategyAlreadyEnabled(address strategy);
    error StrategyNotEnabled(address strategy);
    error InvalidStrategyAsset(address strategy, address expected, address actual);

    address public immutable vault;
    IERC20 public immutable assetToken;

    address[] private _strategies;
    mapping(address => bool) private _enabled;

    /// @notice Principal tracked for cap checks (not including yield).
    mapping(address => uint256) public principalAllocated;

    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event AllocationRecorded(address indexed strategy, uint256 assets);
    event StrategyWithdrawn(address indexed strategy, uint256 requested, uint256 withdrawn);

    constructor(address vault_, address asset_) {
        if (vault_ == address(0) || asset_ == address(0)) revert ZeroAddress();
        vault = vault_;
        assetToken = IERC20(asset_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    function strategies() external view returns (address[] memory) {
        return _strategies;
    }

    function isStrategyEnabled(address strategy) external view returns (bool) {
        return _enabled[strategy];
    }

    function addStrategy(address strategy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_enabled[strategy]) revert StrategyAlreadyEnabled(strategy);

        address expected = address(assetToken);
        address actual = IStrategy(strategy).asset();
        if (actual != expected) revert InvalidStrategyAsset(strategy, expected, actual);

        _enabled[strategy] = true;
        _strategies.push(strategy);

        emit StrategyAdded(strategy);
    }

    function removeStrategy(address strategy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_enabled[strategy]) revert StrategyNotEnabled(strategy);
        _enabled[strategy] = false;
        emit StrategyRemoved(strategy);
        // NOTE: we do not delete from array to keep it simple and stable for indexing.
    }

    function totalStrategyAssets() external view returns (uint256 sum) {
        uint256 len = _strategies.length;
        for (uint256 i = 0; i < len; i++) {
            address s = _strategies[i];
            if (_enabled[s]) {
                sum += IStrategy(s).totalAssets();
            }
        }
    }

    function recordAllocation(address strategy, uint256 assets) external onlyVault {
        if (!_enabled[strategy]) revert StrategyNotEnabled(strategy);
        principalAllocated[strategy] += assets;
        emit AllocationRecorded(strategy, assets);
    }

    function withdrawFromStrategy(address strategy, uint256 assets) public onlyVault returns (uint256 withdrawn) {
        if (!_enabled[strategy]) revert StrategyNotEnabled(strategy);

        withdrawn = IStrategy(strategy).withdraw(assets, vault);

        uint256 p = principalAllocated[strategy];
        if (withdrawn >= p) {
            principalAllocated[strategy] = 0;
        } else {
            principalAllocated[strategy] = p - withdrawn;
        }

        emit StrategyWithdrawn(strategy, assets, withdrawn);
    }

    function withdrawToVault(uint256 assets) external onlyVault returns (uint256 withdrawn) {
        if (assets == 0) return 0;

        uint256 len = _strategies.length;
        for (uint256 i = 0; i < len && withdrawn < assets; i++) {
            address s = _strategies[i];
            if (!_enabled[s]) continue;

            uint256 need = assets - withdrawn;
            uint256 w = withdrawFromStrategy(s, need);
            withdrawn += w;
        }
        // Do not revert here; Vault will enforce post-condition (balance >= needed) and revert if still insufficient.
    }
}
