// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @notice Powered by SwapVM - © Degensoft Ltd 2025. AquaIndex protocol extension opcode set.

import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";
import { Deadline, Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";
import { XYCSwap } from "@1inch/swap-vm/contracts/instructions/XYCSwap.sol";
import { XYCConcentrateSwap } from "@1inch/swap-vm/contracts/instructions/XYCConcentrate.sol";
import { FeeFlatIn } from "@1inch/swap-vm/contracts/instructions/FeeFlat.sol";
import { Jump, JumpIfTokenIn, JumpIfTokenOut } from "@1inch/swap-vm/contracts/instructions/Jumps.sol";

import { IndexNavGuard } from "../instructions/IndexNavGuard.sol";
import { IndexNavPriceAdjuster } from "../instructions/IndexNavPriceAdjuster.sol";
import { IndexInventorySkew } from "../instructions/IndexInventorySkew.sol";
import { IndexMaxTrade } from "../instructions/IndexMaxTrade.sol";
import { IndexCapabilityGuard } from "../instructions/IndexCapabilityGuard.sol";

/// @title AquaIndexOpcodes
/// @notice Explicit combined dispatcher (instruction-set version 1). Upstream opcodes keep their upstream numbers
///         (`OpcodeList`); AquaIndex occupies the previously unallocated bank slots 0xe0-0xe4.
///
///         0x02 Salt  0x05..0x07 Jump*  0x20 Deadline  0x50 XYCSwap  0x51 XYCConcentrateSwap  0x70 FeeFlatIn
///         0xe0 IndexNavGuard  0xe1 IndexNavPriceAdjuster  0xe2 IndexInventorySkew  0xe3 IndexMaxTrade
///         0xe4 IndexCapabilityGuard
///
///         Deliberately narrower than `AquaOpcodes` (no Extruction/external-call, no taker-balance validators, no
///         Decay/PeggedSwap/protocol-fee): fewer instructions a maker could combine to bypass the index guards,
///         and it keeps the router under EIP-170. The exact numbering is verified against the TypeScript SDK in tests.
contract AquaIndexOpcodes {
    error UnknownOpcode(uint256 opcode);

    uint8 public constant INSTRUCTION_SET_VERSION = 1;

    function _runOpcode(Context memory ctx, uint256 opcode, bytes calldata args) internal virtual {
        if (opcode == IndexNavGuard.opcode.asU8()) IndexNavGuard.exec(ctx, args);
        else if (opcode == IndexNavPriceAdjuster.opcode.asU8()) IndexNavPriceAdjuster.exec(ctx, args);
        else if (opcode == IndexInventorySkew.opcode.asU8()) IndexInventorySkew.exec(ctx, args);
        else if (opcode == IndexMaxTrade.opcode.asU8()) IndexMaxTrade.exec(ctx, args);
        else if (opcode == IndexCapabilityGuard.opcode.asU8()) IndexCapabilityGuard.exec(ctx, args);
        else if (opcode == Deadline.opcode.asU8()) Deadline.exec(ctx, args);
        else if (opcode == Salt.opcode.asU8()) Salt.exec(ctx, args);
        else if (opcode == XYCSwap.opcode.asU8()) XYCSwap.exec(ctx, args);
        else if (opcode == XYCConcentrateSwap.opcode.asU8()) XYCConcentrateSwap.exec(ctx, args);
        else if (opcode == FeeFlatIn.opcode.asU8()) FeeFlatIn.exec(ctx, args);
        else if (opcode == Jump.opcode.asU8()) Jump.exec(ctx, args);
        else if (opcode == JumpIfTokenIn.opcode.asU8()) JumpIfTokenIn.exec(ctx, args);
        else if (opcode == JumpIfTokenOut.opcode.asU8()) JumpIfTokenOut.exec(ctx, args);
        else revert UnknownOpcode(opcode);
    }
}
