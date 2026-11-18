// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @notice Holds the real underlying assets of ONE index. Internal ledger (not raw balanceOf) is the accounting
///         source of truth, so donations cannot distort NAV. Only MANAGER_ROLE (Subscription / Redemption /
///         Rebalance managers) can move assets. No Aqua router or market maker has any role here.
contract IndexVault is AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    error AssetNotAllowed(address asset);
    error NotBacked(address asset, uint256 balance, uint256 ledgerAfter);
    error InsufficientHoldings(address asset, uint256 have, uint256 want);

    address[] private _assets;
    mapping(address => bool) public isAllowed;
    mapping(address => uint256) public holdings; // ledger

    event Deposited(address indexed asset, uint256 amount);
    event Withdrawn(address indexed asset, address indexed to, uint256 amount);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function allowAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isAllowed[asset]) {
            isAllowed[asset] = true;
            _assets.push(asset);
        }
    }

    function assets() external view returns (address[] memory) {
        return _assets;
    }

    /// @dev Caller first transfers `amount` to this vault; the vault verifies the real balance covers the new ledger.
    function recordDeposit(address asset, uint256 amount) external onlyRole(MANAGER_ROLE) {
        if (!isAllowed[asset]) revert AssetNotAllowed(asset);
        uint256 ledgerAfter = holdings[asset] + amount;
        uint256 bal = IERC20(asset).balanceOf(address(this));
        if (bal < ledgerAfter) revert NotBacked(asset, bal, ledgerAfter);
        holdings[asset] = ledgerAfter;
        emit Deposited(asset, amount);
    }

    function withdraw(address asset, address to, uint256 amount) external onlyRole(MANAGER_ROLE) whenNotPaused {
        uint256 h = holdings[asset];
        if (h < amount) revert InsufficientHoldings(asset, h, amount);
        holdings[asset] = h - amount;
        IERC20(asset).safeTransfer(to, amount);
        emit Withdrawn(asset, to, amount);
    }

    /// @notice True when the actual token balance covers the ledger for every asset.
    function verifyBacking() external view returns (bool ok) {
        for (uint256 i; i < _assets.length; ++i) {
            if (IERC20(_assets[i]).balanceOf(address(this)) < holdings[_assets[i]]) return false;
        }
        return true;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
