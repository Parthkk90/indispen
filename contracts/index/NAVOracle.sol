// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IndexRegistry } from "./IndexRegistry.sol";
import { IndexVault } from "./IndexVault.sol";
import { NavSnapshot } from "../swapvm/instructions/AquaIndexInterfaces.sol";

/// @notice Asset price book + verified NAV snapshots.
///         Total NAV is always computed ON-CHAIN from the vault ledger x authorised prices; the publisher cannot
///         pass a NAV number, only trigger a publish. Prices are accepted only from PRICE_UPDATER_ROLE, are
///         move-capped per update and expire after `maxPriceAge`.
contract NAVOracle is AccessControl {
    using Math for uint256;

    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant NAV_PUBLISHER_ROLE = keccak256("NAV_PUBLISHER_ROLE");

    error StalePrice(address asset, uint256 updatedAt);
    error PriceNotSet(address asset);
    error PriceMoveTooLarge(address asset, uint256 oldPrice, uint256 newPrice);
    error ZeroPrice();

    struct PriceData {
        uint192 price; // 1e18 USD per whole token
        uint40 updatedAt;
    }

    IndexRegistry public immutable registry;
    uint32 public maxPriceAge = 1 hours;
    uint16 public maxPriceMoveBps = 5000; // 0 disables

    mapping(address => PriceData) private _prices;
    mapping(uint64 => NavSnapshot) private _snap;

    event PriceSet(address indexed asset, uint256 price);
    event NavPublished(uint64 indexed indexId, uint256 navPerShare, uint256 totalNav, uint256 supply, uint64 epoch);
    event ParamsSet(uint32 maxPriceAge, uint16 maxPriceMoveBps);

    constructor(address admin, IndexRegistry registry_) {
        registry = registry_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PRICE_UPDATER_ROLE, admin);
        _grantRole(NAV_PUBLISHER_ROLE, admin);
    }

    function setParams(uint32 maxPriceAge_, uint16 maxPriceMoveBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxPriceAge = maxPriceAge_;
        maxPriceMoveBps = maxPriceMoveBps_;
        emit ParamsSet(maxPriceAge_, maxPriceMoveBps_);
    }

    function setPrice(address asset, uint256 price) external onlyRole(PRICE_UPDATER_ROLE) {
        if (price == 0 || price > type(uint192).max) revert ZeroPrice();
        PriceData memory old = _prices[asset];
        if (old.price != 0 && maxPriceMoveBps != 0) {
            uint256 lo = uint256(old.price) * (10_000 - maxPriceMoveBps) / 10_000;
            uint256 hi = uint256(old.price) * (10_000 + maxPriceMoveBps) / 10_000;
            if (price < lo || price > hi) revert PriceMoveTooLarge(asset, old.price, price);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        _prices[asset] = PriceData(uint192(price), uint40(block.timestamp));
        emit PriceSet(asset, price);
    }

    /// @notice Admin-only reset bypassing the move cap (e.g. after a long outage); still bounded to non-zero.
    function forceSetPrice(address asset, uint256 price) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (price == 0 || price > type(uint192).max) revert ZeroPrice();
        // forge-lint: disable-next-line(unsafe-typecast)
        _prices[asset] = PriceData(uint192(price), uint40(block.timestamp));
        emit PriceSet(asset, price);
    }

    function priceData(address asset) external view returns (uint256 price, uint256 updatedAt) {
        PriceData memory d = _prices[asset];
        return (d.price, d.updatedAt);
    }

    function assetPrice(address asset) public view returns (uint256) {
        PriceData memory d = _prices[asset];
        if (d.price == 0) revert PriceNotSet(asset);
        if (block.timestamp > uint256(d.updatedAt) + maxPriceAge) revert StalePrice(asset, d.updatedAt);
        return d.price;
    }

    /// @notice Value of `amount` raw units of `asset` in 1e18 USD (reverts if the price is stale).
    function valueOf(address asset, uint256 amount) public view returns (uint256) {
        return amount.mulDiv(assetPrice(asset), 10 ** IERC20Metadata(asset).decimals());
    }

    /// @notice Live NAV from vault ledger holdings and fresh prices.
    function computeNav(uint64 indexId) public view returns (uint256 totalNav, uint256 supply, uint256 navPerShare) {
        IndexVault vault = IndexVault(registry.vaultOf(indexId));
        address[] memory a = vault.assets();
        for (uint256 i; i < a.length; ++i) {
            uint256 h = vault.holdings(a[i]);
            if (h != 0) totalNav += valueOf(a[i], h);
        }
        supply = IERC20(registry.shareOf(indexId)).totalSupply();
        navPerShare = supply == 0 ? registry.getIndex(indexId).initialNavPerShare : totalNav.mulDiv(1e18, supply);
    }

    function publishNav(uint64 indexId) external onlyRole(NAV_PUBLISHER_ROLE) returns (NavSnapshot memory s) {
        (uint256 totalNav, uint256 supply, uint256 nps) = computeNav(indexId);
        s = NavSnapshot(nps, totalNav, supply, uint40(block.timestamp), _snap[indexId].epoch + 1);
        _snap[indexId] = s;
        emit NavPublished(indexId, nps, totalNav, supply, s.epoch);
    }

    function navSnapshot(uint64 indexId) external view returns (NavSnapshot memory) {
        return _snap[indexId];
    }

    function isTradable(uint64 indexId) external view returns (bool) {
        address v = registry.vaultOf(indexId);
        return v != address(0) && registry.statusOf(indexId) == IndexRegistry.Status.ACTIVE && !IndexVault(v).paused();
    }

    function shareToken(uint64 indexId) external view returns (address) {
        return registry.shareOf(indexId);
    }
}
