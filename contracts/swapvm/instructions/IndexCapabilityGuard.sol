// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @notice Powered by SwapVM - © Degensoft Ltd 2025. AquaIndex protocol extension instruction.

import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";
import { Opcode } from "@1inch/swap-vm/contracts/libs/OpcodeList.sol";
import { InstructionArgs } from "@1inch/swap-vm/contracts/libs/InstructionArgs.sol";

import { AquaIndexArgs } from "./AquaIndexArgs.sol";
import { Capability, IAquaIndexCapabilities } from "./AquaIndexInterfaces.sol";

/// @notice INDEX_CAPABILITY_GUARD_XD (0xe4): only the delegated operator may fill, within the capability's scope.
/// @dev Args (52 bytes): `[registry:20][capabilityId:32]`. Must run AFTER the price-setting instructions (reads amountIn).
///      Authorization is `ctx.query.taker == capability.operator` (explicit identity, never tx.origin).
///      Stateless: cumulative / windowed spend limits are not supported.
library IndexCapabilityGuard {
    using InstructionArgs for bytes;

    error IndexCapabilityMakerMismatch(address capMaker, address maker);
    error IndexCapabilityUnauthorizedOperator(address taker, address operator);
    error IndexCapabilityRevoked(bytes32 id);
    error IndexCapabilityExpired(bytes32 id, uint40 expiry);
    error IndexCapabilityStaleNonce(uint64 nonce, uint64 minNonce);
    error IndexCapabilityPairNotAllowed(address tokenIn, address tokenOut);
    error IndexCapabilityAmountExceeded(uint256 amountIn, uint128 maxAmountIn);

    Opcode constant opcode = Opcode.IndexCapabilityGuard;
    uint256 internal constant ARGS_LENGTH = 20 + 32;

    function build(address registry, bytes32 capabilityId) internal pure returns (bytes memory) {
        return abi.encodePacked(AquaIndexArgs.header(opcode, ARGS_LENGTH), registry, capabilityId);
    }

    function parse(bytes calldata args) internal pure returns (address registry, bytes32 capabilityId) {
        AquaIndexArgs.requireLength(args, ARGS_LENGTH);
        registry = args.at(0).asAddress();
        capabilityId = args.at(20).asBytes32();
    }

    function exec(Context memory ctx, bytes calldata args) internal view {
        (address registry, bytes32 id) = parse(args);
        AquaIndexArgs.requireTrusted(registry);
        IAquaIndexCapabilities reg = IAquaIndexCapabilities(registry);
        Capability memory c = reg.getCapability(id);

        require(c.maker == ctx.query.maker, IndexCapabilityMakerMismatch(c.maker, ctx.query.maker));
        require(
            c.operator != address(0) && c.operator == ctx.query.taker,
            IndexCapabilityUnauthorizedOperator(ctx.query.taker, c.operator)
        );
        require(!c.revoked, IndexCapabilityRevoked(id));
        require(block.timestamp <= c.expiry, IndexCapabilityExpired(id, c.expiry));
        uint64 minN = reg.minNonce(c.maker);
        require(c.nonce >= minN, IndexCapabilityStaleNonce(c.nonce, minN));

        address tIn = ctx.query.tokenIn;
        address tOut = ctx.query.tokenOut;
        require(
            (tIn == c.tokenA && tOut == c.tokenB) || (tIn == c.tokenB && tOut == c.tokenA),
            IndexCapabilityPairNotAllowed(tIn, tOut)
        );
        require(ctx.swap.amountIn <= c.maxAmountIn, IndexCapabilityAmountExceeded(ctx.swap.amountIn, c.maxAmountIn));
    }
}
