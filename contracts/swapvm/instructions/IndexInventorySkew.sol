// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @notice Powered by SwapVM - © Degensoft Ltd 2025. AquaIndex protocol extension instruction.

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";
import { Opcode } from "@1inch/swap-vm/contracts/libs/OpcodeList.sol";
import { InstructionArgs } from "@1inch/swap-vm/contracts/libs/InstructionArgs.sol";

import { AquaIndexArgs } from "./AquaIndexArgs.sol";
import { IAquaIndexNavSource, NavSnapshot } from "./AquaIndexInterfaces.sol";

/// @notice INDEX_INVENTORY_SKEW_XD (0xe2): price skew from the strategy's Aqua virtual balances. Runs AFTER the
///         price setter (0xe1) and before the limit guards.
/// @dev Args (56 bytes): `[navSource:20][indexId:8][quoteToken:20][targetShareBps:2][maxSkewBps:2][slopeBps:2][maxAdjustBps:2]`
///      ratio     = shareValue / (shareValue + quoteValue) in bps, values from `ctx.swap.balanceIn/Out` (Aqua virtual
///                  balances of this strategy, never wallet balances), shares valued at NAV, quote at oracle price
///      imbalance = ratio - target        (>0: maker holds too many shares)
///      adjust    = min(|imbalance| x slope / 1e4, maxAdjust)  bps applied to the share price: lower when long shares,
///                  higher when short. Applies to both directions, so it is monotone in imbalance.
///      A swap that would leave |post imbalance| > maxSkew is rejected unless it does not worsen the imbalance.
library IndexInventorySkew {
    using InstructionArgs for bytes;
    using Math for uint256;

    error IndexSkewInvalidParams();
    error IndexSkewInvalidPair(address tokenIn, address tokenOut);
    error IndexSkewDepletedInventory();
    error IndexSkewInsufficientLiquidity(uint256 balanceOut, uint256 amountOut);
    error IndexSkewMaxExceeded(uint256 postImbalanceBps, uint16 maxSkewBps);

    Opcode constant opcode = Opcode.IndexInventorySkew;
    uint256 internal constant ARGS_LENGTH = 20 + 8 + 20 + 2 + 2 + 2 + 2;

    struct Params {
        address navSource;
        uint64 indexId;
        address quoteToken;
        uint16 targetShareBps;
        uint16 maxSkewBps;
        uint16 slopeBps;
        uint16 maxAdjustBps;
    }

    struct Inv {
        address share;
        bool buy; // taker buys shares
        uint256 navPerShare;
        uint256 quotePrice;
        uint256 shareUnit;
        uint256 quoteUnit;
    }

    function validate(Params memory p) internal pure {
        require(
            p.targetShareBps <= AquaIndexArgs.BPS && p.maxSkewBps <= AquaIndexArgs.BPS && p.maxAdjustBps <= 5000,
            IndexSkewInvalidParams()
        );
    }

    function build(Params memory p) internal pure returns (bytes memory) {
        validate(p);
        return abi.encodePacked(
            AquaIndexArgs.header(opcode, ARGS_LENGTH),
            p.navSource,
            p.indexId,
            p.quoteToken,
            p.targetShareBps,
            p.maxSkewBps,
            p.slopeBps,
            p.maxAdjustBps
        );
    }

    function parse(bytes calldata args) internal pure returns (Params memory p) {
        AquaIndexArgs.requireLength(args, ARGS_LENGTH);
        p.navSource = args.at(0).asAddress();
        p.indexId = args.at(20).asU64();
        p.quoteToken = args.at(28).asAddress();
        p.targetShareBps = args.at(48).asU16();
        p.maxSkewBps = args.at(50).asU16();
        p.slopeBps = args.at(52).asU16();
        p.maxAdjustBps = args.at(54).asU16();
    }

    function _ratioBps(Inv memory v, uint256 shareBal, uint256 quoteBal) private pure returns (uint256) {
        uint256 shareVal = shareBal.mulDiv(v.navPerShare, v.shareUnit);
        uint256 total = shareVal + quoteBal.mulDiv(v.quotePrice, v.quoteUnit);
        require(total != 0, IndexSkewDepletedInventory());
        return shareVal.mulDiv(AquaIndexArgs.BPS, total);
    }

    function _abs(int256 x) private pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function exec(Context memory ctx, bytes calldata args) internal view {
        Params memory p = parse(args);
        validate(p);
        AquaIndexArgs.requireTrusted(p.navSource);
        IAquaIndexNavSource src = IAquaIndexNavSource(p.navSource);

        Inv memory v;
        v.share = src.shareToken(p.indexId);
        v.buy = ctx.query.tokenOut == v.share && ctx.query.tokenIn == p.quoteToken;
        require(
            v.buy || (ctx.query.tokenIn == v.share && ctx.query.tokenOut == p.quoteToken),
            IndexSkewInvalidPair(ctx.query.tokenIn, ctx.query.tokenOut)
        );
        NavSnapshot memory s = src.navSnapshot(p.indexId);
        v.navPerShare = s.navPerShare;
        v.quotePrice = src.assetPrice(p.quoteToken);
        v.shareUnit = 10 ** IERC20Metadata(v.share).decimals();
        v.quoteUnit = 10 ** IERC20Metadata(p.quoteToken).decimals();

        uint256 shareBal = v.buy ? ctx.swap.balanceOut : ctx.swap.balanceIn;
        uint256 quoteBal = v.buy ? ctx.swap.balanceIn : ctx.swap.balanceOut;
        // forge-lint: disable-start(unsafe-typecast)
        int256 imb = int256(_ratioBps(v, shareBal, quoteBal)) - int256(uint256(p.targetShareBps));
        // forge-lint: disable-end(unsafe-typecast)

        // Price impact: the adjustment is evaluated at the POST-trade inventory (from the unskewed amounts), which is
        // never more favourable to the taker than the pre-trade inventory. A round trip therefore cannot profit from
        // the skew itself.
        require(
            ctx.swap.amountOut <= ctx.swap.balanceOut,
            IndexSkewInsufficientLiquidity(ctx.swap.balanceOut, ctx.swap.amountOut)
        );
        // forge-lint: disable-start(unsafe-typecast)
        int256 imbPost = int256(
            _ratioBps(
                v,
                v.buy ? shareBal - ctx.swap.amountOut : shareBal + ctx.swap.amountIn,
                v.buy ? quoteBal + ctx.swap.amountIn : quoteBal - ctx.swap.amountOut
            )
        ) - int256(uint256(p.targetShareBps));
        // forge-lint: disable-end(unsafe-typecast)
        uint256 adj = Math.min(_abs(imbPost) * p.slopeBps / AquaIndexArgs.BPS, p.maxAdjustBps);
        // price factor f = (1e4 - sAdj)/1e4: sAdj > 0 lowers the share price (maker long shares)
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 sAdj = imbPost >= 0 ? int256(adj) : -int256(adj);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 f = uint256(int256(AquaIndexArgs.BPS) - sAdj);

        if (ctx.query.isExactIn) {
            ctx.swap.amountOut =
                v.buy ? ctx.swap.amountOut.mulDiv(AquaIndexArgs.BPS, f) : ctx.swap.amountOut.mulDiv(f, AquaIndexArgs.BPS);
        } else {
            ctx.swap.amountIn = v.buy
                ? ctx.swap.amountIn.mulDiv(f, AquaIndexArgs.BPS, Math.Rounding.Ceil)
                : ctx.swap.amountIn.mulDiv(AquaIndexArgs.BPS, f, Math.Rounding.Ceil);
        }

        require(
            ctx.swap.amountOut <= ctx.swap.balanceOut,
            IndexSkewInsufficientLiquidity(ctx.swap.balanceOut, ctx.swap.amountOut)
        );
        uint256 postShare = v.buy ? shareBal - ctx.swap.amountOut : shareBal + ctx.swap.amountIn;
        uint256 postQuote = v.buy ? quoteBal + ctx.swap.amountIn : quoteBal - ctx.swap.amountOut;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 postDev = _abs(int256(_ratioBps(v, postShare, postQuote)) - int256(uint256(p.targetShareBps)));
        require(postDev <= p.maxSkewBps || postDev <= _abs(imb), IndexSkewMaxExceeded(postDev, p.maxSkewBps));
    }
}
