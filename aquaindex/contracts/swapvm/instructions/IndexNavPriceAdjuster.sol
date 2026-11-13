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

/// @notice INDEX_NAV_PRICE_ADJUSTER_XD (0xe1): NAV-anchored price of an index share against a quote token.
/// @dev Args (59 bytes):
///      `[navSource:20][indexId:8][quoteToken:20][premiumBps:int16][maxPremiumBps:2][maxDiscountBps:2]`
///      `[spreadBps:2][feeBps:2][mode:1]`
///
///      fair  = navPerShare x (1 + premium) / quotePrice          (quote units per share, 1e18)
///      ask   = fair x (1 + spread + fee)   (taker buys shares)    rounded up   (favours maker)
///      bid   = fair x (1 - spread - fee)   (taker sells shares)   rounded down (favours maker)
///      The premium is fixed by the maker inside the strategy hash and must lie in [-maxDiscount, +maxPremium];
///      the taker never supplies a price. mode 0 = SET (this instruction defines the amounts); mode 1 = CAP (an
///      earlier curve defines amounts, this instruction only clamps them so the taker never gets a better price than
///      the NAV-derived one).
library IndexNavPriceAdjuster {
    using InstructionArgs for bytes;
    using Math for uint256;

    error IndexNavPriceInvalidParams();
    error IndexNavPricePremiumOutOfBounds(int16 premiumBps, uint16 maxPremiumBps, uint16 maxDiscountBps);
    error IndexNavPriceInvalidPair(address tokenIn, address tokenOut);
    error IndexNavPriceNoNav(uint64 indexId);
    error IndexNavPriceZeroPrice();

    Opcode constant opcode = Opcode.IndexNavPriceAdjuster;
    uint256 internal constant ARGS_LENGTH = 20 + 8 + 20 + 2 + 2 + 2 + 2 + 2 + 1;
    uint8 internal constant MODE_SET = 0;
    uint8 internal constant MODE_CAP = 1;

    struct Params {
        address navSource;
        uint64 indexId;
        address quoteToken;
        int16 premiumBps;
        uint16 maxPremiumBps;
        uint16 maxDiscountBps;
        uint16 spreadBps;
        uint16 feeBps;
        uint8 mode;
    }

    function validate(Params memory p) internal pure {
        require(p.mode <= MODE_CAP, IndexNavPriceInvalidParams());
        require(p.maxPremiumBps < AquaIndexArgs.BPS && p.maxDiscountBps < AquaIndexArgs.BPS, IndexNavPriceInvalidParams());
        require(
            p.premiumBps <= int256(uint256(p.maxPremiumBps)) && p.premiumBps >= -int256(uint256(p.maxDiscountBps)),
            IndexNavPricePremiumOutOfBounds(p.premiumBps, p.maxPremiumBps, p.maxDiscountBps)
        );
        require(uint256(p.spreadBps) + p.feeBps < AquaIndexArgs.BPS, IndexNavPriceInvalidParams());
    }

    function build(Params memory p) internal pure returns (bytes memory) {
        validate(p);
        return abi.encodePacked(
            AquaIndexArgs.header(opcode, ARGS_LENGTH),
            p.navSource,
            p.indexId,
            p.quoteToken,
            p.premiumBps,
            p.maxPremiumBps,
            p.maxDiscountBps,
            p.spreadBps,
            p.feeBps,
            p.mode
        );
    }

    function parse(bytes calldata args) internal pure returns (Params memory p) {
        AquaIndexArgs.requireLength(args, ARGS_LENGTH);
        p.navSource = args.at(0).asAddress();
        p.indexId = args.at(20).asU64();
        p.quoteToken = args.at(28).asAddress();
        p.premiumBps = int16(args.at(48).asU16());
        p.maxPremiumBps = args.at(50).asU16();
        p.maxDiscountBps = args.at(52).asU16();
        p.spreadBps = args.at(54).asU16();
        p.feeBps = args.at(56).asU16();
        p.mode = args.at(58).asU8();
    }

    /// @dev Quote-per-share price (1e18) for the taker's direction, rounded in the maker's favour.
    function price(Params memory p, bool takerBuysShares) internal view returns (uint256) {
        NavSnapshot memory s = IAquaIndexNavSource(p.navSource).navSnapshot(p.indexId);
        require(s.navPerShare != 0, IndexNavPriceNoNav(p.indexId));
        uint256 quotePrice = IAquaIndexNavSource(p.navSource).assetPrice(p.quoteToken);
        require(quotePrice != 0, IndexNavPriceZeroPrice());

        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 factor = uint256(int256(AquaIndexArgs.BPS) + p.premiumBps);
        uint256 fair = s.navPerShare.mulDiv(factor, AquaIndexArgs.BPS).mulDiv(1e18, quotePrice);
        uint256 widen = uint256(p.spreadBps) + p.feeBps;
        uint256 px = takerBuysShares
            ? fair.mulDiv(AquaIndexArgs.BPS + widen, AquaIndexArgs.BPS, Math.Rounding.Ceil)
            : fair.mulDiv(AquaIndexArgs.BPS - widen, AquaIndexArgs.BPS);
        require(px != 0, IndexNavPriceZeroPrice());
        return px;
    }

    function exec(Context memory ctx, bytes calldata args) internal view {
        Params memory p = parse(args);
        validate(p);
        AquaIndexArgs.requireTrusted(p.navSource);

        address share = IAquaIndexNavSource(p.navSource).shareToken(p.indexId);
        bool buy = ctx.query.tokenOut == share && ctx.query.tokenIn == p.quoteToken;
        require(
            buy || (ctx.query.tokenIn == share && ctx.query.tokenOut == p.quoteToken),
            IndexNavPriceInvalidPair(ctx.query.tokenIn, ctx.query.tokenOut)
        );

        uint256 px = price(p, buy);
        uint256 shareUnit = 10 ** IERC20Metadata(share).decimals();
        uint256 quoteUnit = 10 ** IERC20Metadata(p.quoteToken).decimals();
        // raw quote = raw shares x px x quoteUnit / (1e18 x shareUnit)
        uint256 qNum = px * quoteUnit;
        uint256 qDen = 1e18 * shareUnit;
        bool cap = p.mode == MODE_CAP;

        if (ctx.query.isExactIn) {
            uint256 out = buy ? ctx.swap.amountIn.mulDiv(qDen, qNum) : ctx.swap.amountIn.mulDiv(qNum, qDen);
            ctx.swap.amountOut = cap && ctx.swap.amountOut < out ? ctx.swap.amountOut : out;
        } else {
            uint256 inn = buy
                ? ctx.swap.amountOut.mulDiv(qNum, qDen, Math.Rounding.Ceil)
                : ctx.swap.amountOut.mulDiv(qDen, qNum, Math.Rounding.Ceil);
            ctx.swap.amountIn = cap && ctx.swap.amountIn > inn ? ctx.swap.amountIn : inn;
        }
    }
}
