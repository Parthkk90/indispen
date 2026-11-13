// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IndexRegistry } from "./IndexRegistry.sol";
import { IndexVault } from "./IndexVault.sol";
import { IndexShare } from "./IndexShare.sol";
import { NAVOracle } from "./NAVOracle.sol";

/// @notice Burns shares and pays out either pro-rata in kind (every vault asset) or in USDC when the vault actually
///         holds enough USDC (no forced liquidation). A redeemer can never receive more than their pro-rata claim.
contract RedemptionManager is ReentrancyGuard {
    using Math for uint256;

    error NotRedeemable(uint64 indexId);
    error InsufficientQuoteLiquidity(uint256 want, uint256 have);
    error SlippageExceeded(uint256 out, uint256 minOut);
    error ZeroAmount();

    IndexRegistry public immutable registry;
    NAVOracle public immutable oracle;

    event RedeemedInKind(uint64 indexed indexId, address indexed user, uint256 shares);
    event RedeemedToQuote(uint64 indexed indexId, address indexed user, uint256 shares, uint256 quoteOut);

    constructor(IndexRegistry registry_, NAVOracle oracle_) {
        registry = registry_;
        oracle = oracle_;
    }

    function previewInKind(uint64 indexId, uint256 shares)
        public
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        IndexVault v = IndexVault(registry.vaultOf(indexId));
        uint256 supply = IERC20(registry.shareOf(indexId)).totalSupply();
        uint16 fee = registry.getIndex(indexId).redemptionFeeBps;
        assets = v.assets();
        amounts = new uint256[](assets.length);
        for (uint256 i; i < assets.length; ++i) {
            uint256 a = v.holdings(assets[i]).mulDiv(shares, supply);
            amounts[i] = a - a * fee / 10_000;
        }
    }

    function previewToQuote(uint64 indexId, uint256 shares) public view returns (uint256 out) {
        (uint256 totalNav, uint256 supply,) = oracle.computeNav(indexId);
        address q = registry.quoteAsset();
        uint256 value = totalNav.mulDiv(shares, supply);
        out = value.mulDiv(10 ** IERC20Metadata(q).decimals(), oracle.assetPrice(q));
        out -= out * registry.getIndex(indexId).redemptionFeeBps / 10_000;
    }

    function redeemInKind(uint64 indexId, uint256 shares) external nonReentrant {
        if (shares == 0) revert ZeroAmount();
        if (registry.statusOf(indexId) == IndexRegistry.Status.NONE) revert NotRedeemable(indexId);
        (address[] memory assets, uint256[] memory amounts) = previewInKind(indexId, shares);
        IndexShare(registry.shareOf(indexId)).burn(msg.sender, shares);
        IndexVault v = IndexVault(registry.vaultOf(indexId));
        for (uint256 i; i < assets.length; ++i) {
            if (amounts[i] != 0) v.withdraw(assets[i], msg.sender, amounts[i]);
        }
        emit RedeemedInKind(indexId, msg.sender, shares);
    }

    function redeemToQuote(uint64 indexId, uint256 shares, uint256 minOut) external nonReentrant returns (uint256 out) {
        if (shares == 0) revert ZeroAmount();
        if (registry.statusOf(indexId) == IndexRegistry.Status.NONE) revert NotRedeemable(indexId);
        out = previewToQuote(indexId, shares); // before the burn: supply still includes `shares`
        if (out < minOut) revert SlippageExceeded(out, minOut);
        IndexVault v = IndexVault(registry.vaultOf(indexId));
        address q = registry.quoteAsset();
        uint256 have = v.holdings(q);
        if (have < out) revert InsufficientQuoteLiquidity(out, have);
        IndexShare(registry.shareOf(indexId)).burn(msg.sender, shares);
        v.withdraw(q, msg.sender, out);
        emit RedeemedToQuote(indexId, msg.sender, shares, out);
    }
}
