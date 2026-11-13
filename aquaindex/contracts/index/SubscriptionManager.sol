// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IndexRegistry } from "./IndexRegistry.sol";
import { IndexVault } from "./IndexVault.sol";
import { IndexShare } from "./IndexShare.sol";
import { NAVOracle } from "./NAVOracle.sol";

/// @notice Quote-asset (USDC) subscription: deposits into the vault at on-chain NAV and mints shares.
contract SubscriptionManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    error NotActive(uint64 indexId);
    error SlippageExceeded(uint256 shares, uint256 minShares);
    error ZeroShares();
    error NavZero();

    IndexRegistry public immutable registry;
    NAVOracle public immutable oracle;

    event Subscribed(uint64 indexed indexId, address indexed user, uint256 amountIn, uint256 shares, uint256 navPerShare);

    constructor(IndexRegistry registry_, NAVOracle oracle_) {
        registry = registry_;
        oracle = oracle_;
    }

    function quote(uint64 indexId, uint256 amount) public view returns (uint256 shares, uint256 navPerShare) {
        IndexRegistry.Index memory ix = registry.getIndex(indexId);
        (uint256 totalNav, uint256 supply, uint256 nps) = oracle.computeNav(indexId);
        address q = registry.quoteAsset();
        uint256 value = oracle.valueOf(q, amount);
        if (supply == 0) {
            shares = value.mulDiv(1e18, ix.initialNavPerShare);
        } else {
            if (totalNav == 0) revert NavZero();
            shares = value.mulDiv(supply, totalNav);
        }
        shares -= shares * ix.subscriptionFeeBps / 10_000;
        navPerShare = nps;
    }

    function subscribe(uint64 indexId, uint256 amount, uint256 minShares) external nonReentrant returns (uint256 shares) {
        if (registry.statusOf(indexId) != IndexRegistry.Status.ACTIVE) revert NotActive(indexId);
        uint256 nps;
        (shares, nps) = quote(indexId, amount); // priced BEFORE the deposit
        if (shares == 0) revert ZeroShares();
        if (shares < minShares) revert SlippageExceeded(shares, minShares);

        IndexVault vault = IndexVault(registry.vaultOf(indexId));
        IERC20 q = IERC20(registry.quoteAsset());
        q.safeTransferFrom(msg.sender, address(vault), amount);
        vault.recordDeposit(address(q), amount);
        IndexShare(registry.shareOf(indexId)).mint(msg.sender, shares);
        emit Subscribed(indexId, msg.sender, amount, shares, nps);
    }
}
