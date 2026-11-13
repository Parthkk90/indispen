// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";

import { IndexRegistry } from "./IndexRegistry.sol";
import { IndexVault } from "./IndexVault.sol";
import { NAVOracle } from "./NAVOracle.sol";

/// @notice Drift analysis, rebalance proposals and constrained execution through a SwapVM router/Aqua strategy.
///         The vault is NEVER approved to the router: this manager withdraws exactly `sellAmount`, swaps as taker,
///         and returns every resulting token to the vault. Execution is bounded by on-chain price checks
///         (oracle value in vs out), a max trade size relative to NAV and a REBALANCER_ROLE.
contract RebalanceManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    error NotActive(uint64 indexId);
    error AssetNotAllowed(address asset);
    error TradeTooLarge(uint256 valueIn, uint256 maxValue);
    error SlippageTooHigh(uint256 valueIn, uint256 valueOut);
    error MinOutNotMet(uint256 out, uint256 minOut);
    error DriftNotImproved();
    error SameAsset();

    struct AssetDrift {
        address asset;
        uint256 currentValue; // 1e18 USD
        uint256 targetValue;
        int256 driftBps; // current weight - target weight, bps of NAV
        int256 deltaValue; // target - current (>0 buy, <0 sell)
        int256 deltaAmount; // same in raw token units
    }

    struct TradeProposal {
        address sellAsset;
        address buyAsset;
        uint256 sellValue; // 1e18 USD
        uint256 sellAmount; // raw
    }

    IndexRegistry public immutable registry;
    NAVOracle public immutable oracle;
    address public immutable router;

    uint16 public maxTradeBps = 2500; // of NAV per execution
    uint16 public maxSlippageBps = 100; // oracle value out vs in

    event ParamsSet(uint16 maxTradeBps, uint16 maxSlippageBps);
    event Rebalanced(
        uint64 indexed indexId, address sellAsset, address buyAsset, uint256 sold, uint256 bought, bytes32 orderHash
    );

    constructor(address admin, IndexRegistry registry_, NAVOracle oracle_, address router_) {
        registry = registry_;
        oracle = oracle_;
        router = router_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REBALANCER_ROLE, admin);
    }

    function setParams(uint16 maxTradeBps_, uint16 maxSlippageBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(maxTradeBps_ <= 10_000 && maxSlippageBps_ < 5000, "params");
        maxTradeBps = maxTradeBps_;
        maxSlippageBps = maxSlippageBps_;
        emit ParamsSet(maxTradeBps_, maxSlippageBps_);
    }

    /// @notice Current vs target weights of every constituent plus the quote asset (target 0: idle cash is drift).
    function drift(uint64 indexId) public view returns (uint256 totalNav, AssetDrift[] memory d) {
        (address[] memory c, uint16[] memory w) = registry.constituentsOf(indexId);
        IndexVault v = IndexVault(registry.vaultOf(indexId));
        (totalNav,,) = oracle.computeNav(indexId);
        address q = registry.quoteAsset();
        d = new AssetDrift[](c.length + 1);
        for (uint256 i; i <= c.length; ++i) {
            address a = i < c.length ? c[i] : q;
            uint256 tw = i < c.length ? w[i] : 0;
            uint256 cur = oracle.valueOf(a, v.holdings(a));
            uint256 tgt = totalNav * tw / 10_000;
            d[i].asset = a;
            d[i].currentValue = cur;
            d[i].targetValue = tgt;
            // forge-lint: disable-start(unsafe-typecast)
            d[i].deltaValue = int256(tgt) - int256(cur);
            d[i].driftBps = totalNav == 0 ? int256(0) : (int256(cur) - int256(tgt)) * 10_000 / int256(totalNav);
            uint256 price = oracle.assetPrice(a);
            uint256 unit = 10 ** _dec(a);
            uint256 absAmt = _abs(d[i].deltaValue).mulDiv(unit, price);
            d[i].deltaAmount = d[i].deltaValue >= 0 ? int256(absAmt) : -int256(absAmt);
            // forge-lint: disable-end(unsafe-typecast)
        }
    }

    /// @notice Greedy pairing of overweight assets (sell) with underweight assets (buy); trades below `minValue` skipped.
    function propose(uint64 indexId, uint256 minValue) external view returns (TradeProposal[] memory out) {
        (, AssetDrift[] memory d) = drift(indexId);
        uint256 n = d.length;
        uint256[] memory sellLeft = new uint256[](n);
        uint256[] memory buyLeft = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            if (d[i].deltaValue < 0) sellLeft[i] = _abs(d[i].deltaValue);
            else buyLeft[i] = uint256(d[i].deltaValue);
        }
        TradeProposal[] memory tmp = new TradeProposal[](n * n);
        uint256 k;
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n && sellLeft[i] != 0; ++j) {
                if (buyLeft[j] == 0) continue;
                uint256 v = Math.min(sellLeft[i], buyLeft[j]);
                sellLeft[i] -= v;
                buyLeft[j] -= v;
                if (v < minValue) continue;
                tmp[k++] = TradeProposal(
                    d[i].asset, d[j].asset, v, v.mulDiv(10 ** _dec(d[i].asset), oracle.assetPrice(d[i].asset))
                );
            }
        }
        out = new TradeProposal[](k);
        for (uint256 i; i < k; ++i) {
            out[i] = tmp[i];
        }
    }

    /// @notice Execute one rebalance trade against any SwapVM order (typically an Aqua strategy on `router`).
    /// @dev `takerData` must be built with taker = this contract and `useTransferFromAndAquaPush` for Aqua orders.
    function execute(
        uint64 indexId,
        address sellAsset,
        address buyAsset,
        uint256 sellAmount,
        ISwapVM.Order calldata order,
        bytes calldata takerData,
        uint256 minBuyOut
    ) external onlyRole(REBALANCER_ROLE) nonReentrant returns (uint256 sold, uint256 bought) {
        if (registry.statusOf(indexId) != IndexRegistry.Status.ACTIVE) revert NotActive(indexId);
        if (sellAsset == buyAsset) revert SameAsset();
        IndexVault v = IndexVault(registry.vaultOf(indexId));
        if (!v.isAllowed(sellAsset)) revert AssetNotAllowed(sellAsset);
        if (!v.isAllowed(buyAsset)) revert AssetNotAllowed(buyAsset);

        (uint256 totalNav,,) = oracle.computeNav(indexId);
        uint256 maxValue = totalNav * maxTradeBps / 10_000;
        uint256 valueIn = oracle.valueOf(sellAsset, sellAmount);
        if (valueIn > maxValue) revert TradeTooLarge(valueIn, maxValue);
        (, AssetDrift[] memory before) = drift(indexId);

        uint256 sellBefore = IERC20(sellAsset).balanceOf(address(this));
        uint256 buyBefore = IERC20(buyAsset).balanceOf(address(this));
        v.withdraw(sellAsset, address(this), sellAmount);
        IERC20(sellAsset).forceApprove(router, sellAmount);
        (,, bytes32 orderHash) = _swap(order, sellAmount, takerData);
        IERC20(sellAsset).forceApprove(router, 0);

        sold = sellAmount - (IERC20(sellAsset).balanceOf(address(this)) - sellBefore);
        bought = IERC20(buyAsset).balanceOf(address(this)) - buyBefore;
        if (bought < minBuyOut) revert MinOutNotMet(bought, minBuyOut);
        uint256 valueOut = oracle.valueOf(buyAsset, bought);
        uint256 soldValue = oracle.valueOf(sellAsset, sold);
        if (valueOut < soldValue * (10_000 - maxSlippageBps) / 10_000) revert SlippageTooHigh(soldValue, valueOut);

        // everything goes back into the vault
        uint256 left = IERC20(sellAsset).balanceOf(address(this)) - sellBefore;
        if (left != 0) _toVault(v, sellAsset, left);
        _toVault(v, buyAsset, bought);

        // a rebalance must not increase the maximum absolute drift
        (, AssetDrift[] memory afterD) = drift(indexId);
        if (_maxAbsDrift(afterD) > _maxAbsDrift(before)) revert DriftNotImproved();
        emit Rebalanced(indexId, sellAsset, buyAsset, sold, bought, orderHash);
    }

    function _swap(ISwapVM.Order calldata order, uint256 amount, bytes calldata takerData)
        private
        returns (uint256 a, uint256 b, bytes32 h)
    {
        return ISwapVM(router).swap(order, amount, takerData);
    }

    function _toVault(IndexVault v, address asset, uint256 amount) private {
        IERC20(asset).safeTransfer(address(v), amount);
        v.recordDeposit(asset, amount);
    }

    function _maxAbsDrift(AssetDrift[] memory d) private pure returns (uint256 m) {
        for (uint256 i; i < d.length; ++i) {
            uint256 a = _abs(d[i].driftBps);
            if (a > m) m = a;
        }
    }

    function _abs(int256 x) private pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function _dec(address a) private view returns (uint8) {
        (bool ok, bytes memory r) = a.staticcall(abi.encodeWithSignature("decimals()"));
        require(ok && r.length == 32, "decimals");
        return abi.decode(r, (uint8));
    }
}
