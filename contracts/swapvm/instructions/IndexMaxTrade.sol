// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @notice Powered by SwapVM - © Degensoft Ltd 2025. AquaIndex protocol extension instruction.

import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";
import { Opcode } from "@1inch/swap-vm/contracts/libs/OpcodeList.sol";
import { InstructionArgs } from "@1inch/swap-vm/contracts/libs/InstructionArgs.sol";

import { AquaIndexArgs } from "./AquaIndexArgs.sol";
import { IAquaIndexNavSource } from "./AquaIndexInterfaces.sol";

/// @notice INDEX_MAX_TRADE_XD (0xe3): stateless per-swap limits. Must run AFTER the price-setting instructions.
/// @dev Args (76 bytes): `[navSource:20][indexId:8][maxAmountIn:16][maxAmountOut:16][minLiquidityOut:16]`
///        0 disables the respective cap. `minLiquidityOut` is the minimum Aqua virtual tokenOut balance that must
///        remain after the swap. Also rejects pairs that do not contain the index share, and paused indices.
///      Cumulative limits are intentionally not implemented here: quotes are read-only and cannot consume quota.
library IndexMaxTrade {
    using InstructionArgs for bytes;

    error IndexMaxTradeInvalidPair(address tokenIn, address tokenOut);
    error IndexMaxTradePaused(uint64 indexId);
    error IndexMaxTradeInAmount(uint256 amountIn, uint128 maxAmountIn);
    error IndexMaxTradeOutAmount(uint256 amountOut, uint128 maxAmountOut);
    error IndexMaxTradeInsufficientLiquidity(uint256 balanceOut, uint256 amountOut, uint128 minLiquidityOut);
    error IndexMaxTradeZeroAmount();

    Opcode constant opcode = Opcode.IndexMaxTrade;
    uint256 internal constant ARGS_LENGTH = 20 + 8 + 16 + 16 + 16;

    function build(
        address navSource,
        uint64 indexId,
        uint128 maxAmountIn,
        uint128 maxAmountOut,
        uint128 minLiquidityOut
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            AquaIndexArgs.header(opcode, ARGS_LENGTH), navSource, indexId, maxAmountIn, maxAmountOut, minLiquidityOut
        );
    }

    function parse(bytes calldata args)
        internal
        pure
        returns (address navSource, uint64 indexId, uint128 maxIn, uint128 maxOut, uint128 minLiq)
    {
        AquaIndexArgs.requireLength(args, ARGS_LENGTH);
        navSource = args.at(0).asAddress();
        indexId = args.at(20).asU64();
        maxIn = args.at(28).asU128();
        maxOut = args.at(44).asU128();
        minLiq = args.at(60).asU128();
    }

    function exec(Context memory ctx, bytes calldata args) internal view {
        (address navSource, uint64 indexId, uint128 maxIn, uint128 maxOut, uint128 minLiq) = parse(args);
        AquaIndexArgs.requireTrusted(navSource);
        IAquaIndexNavSource src = IAquaIndexNavSource(navSource);

        address share = src.shareToken(indexId);
        require(
            ctx.query.tokenIn != ctx.query.tokenOut && (ctx.query.tokenIn == share || ctx.query.tokenOut == share),
            IndexMaxTradeInvalidPair(ctx.query.tokenIn, ctx.query.tokenOut)
        );
        require(src.isTradable(indexId), IndexMaxTradePaused(indexId));

        uint256 amountIn = ctx.swap.amountIn;
        uint256 amountOut = ctx.swap.amountOut;
        require(amountIn != 0 && amountOut != 0, IndexMaxTradeZeroAmount());
        require(maxIn == 0 || amountIn <= maxIn, IndexMaxTradeInAmount(amountIn, maxIn));
        require(maxOut == 0 || amountOut <= maxOut, IndexMaxTradeOutAmount(amountOut, maxOut));
        uint256 balanceOut = ctx.swap.balanceOut;
        require(
            balanceOut >= amountOut && balanceOut - amountOut >= minLiq,
            IndexMaxTradeInsufficientLiquidity(balanceOut, amountOut, minLiq)
        );
    }
}
