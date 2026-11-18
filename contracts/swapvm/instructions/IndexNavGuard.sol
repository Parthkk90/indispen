// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @notice Powered by SwapVM - © Degensoft Ltd 2025. AquaIndex protocol extension instruction.

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";
import { Opcode } from "@1inch/swap-vm/contracts/libs/OpcodeList.sol";
import { InstructionArgs } from "@1inch/swap-vm/contracts/libs/InstructionArgs.sol";

import { AquaIndexArgs } from "./AquaIndexArgs.sol";
import { IAquaIndexNavSource, NavSnapshot } from "./AquaIndexInterfaces.sol";

/// @notice INDEX_NAV_GUARD_XD (0xe0): reject trading on stale, inactive or inconsistent NAV. Pure guard, no registers.
/// @dev Args (42 bytes): `[navSource:20][indexId:8][maxNavAge:4][minEpoch:8][maxDeviationBps:2]`
///        - navSource   trusted NAV oracle (router allowlist)
///        - maxNavAge   seconds; snapshot must satisfy `now - updatedAt <= maxNavAge`
///        - minEpoch    snapshot epoch must be >= this (and non-zero)
///        - maxDeviationBps  |navPerShare - totalNav/currentSupply| / navPerShare. Detects share supply that has moved
///                      since the NAV was verified (mint/burn after publish).
library IndexNavGuard {
    using InstructionArgs for bytes;

    error IndexNavGuardInactive(uint64 indexId);
    error IndexNavGuardNoSnapshot(uint64 indexId);
    error IndexNavGuardStale(uint256 age, uint32 maxAge);
    error IndexNavGuardEpoch(uint64 epoch, uint64 minEpoch);
    error IndexNavGuardDeviation(uint256 deviationBps, uint16 maxBps);

    Opcode constant opcode = Opcode.IndexNavGuard;
    uint256 internal constant ARGS_LENGTH = 20 + 8 + 4 + 8 + 2;

    function build(address navSource, uint64 indexId, uint32 maxNavAge, uint64 minEpoch, uint16 maxDeviationBps)
        internal
        pure
        returns (bytes memory)
    {
        require(maxDeviationBps <= AquaIndexArgs.BPS, AquaIndexArgs.AquaIndexBadArgsLength(AquaIndexArgs.BPS, maxDeviationBps));
        return abi.encodePacked(
            AquaIndexArgs.header(opcode, ARGS_LENGTH), navSource, indexId, maxNavAge, minEpoch, maxDeviationBps
        );
    }

    function parse(bytes calldata args)
        internal
        pure
        returns (address navSource, uint64 indexId, uint32 maxNavAge, uint64 minEpoch, uint16 maxDeviationBps)
    {
        AquaIndexArgs.requireLength(args, ARGS_LENGTH);
        navSource = args.at(0).asAddress();
        indexId = args.at(20).asU64();
        maxNavAge = args.at(28).asU32();
        minEpoch = args.at(32).asU64();
        maxDeviationBps = args.at(40).asU16();
    }

    function exec(Context memory, bytes calldata args) internal view {
        (address navSource, uint64 indexId, uint32 maxNavAge, uint64 minEpoch, uint16 maxDeviationBps) = parse(args);
        AquaIndexArgs.requireTrusted(navSource);
        IAquaIndexNavSource src = IAquaIndexNavSource(navSource);

        require(src.isTradable(indexId), IndexNavGuardInactive(indexId));
        NavSnapshot memory s = src.navSnapshot(indexId);
        require(s.updatedAt != 0 && s.navPerShare != 0, IndexNavGuardNoSnapshot(indexId));

        uint256 age = block.timestamp - s.updatedAt;
        require(age <= maxNavAge, IndexNavGuardStale(age, maxNavAge));
        require(s.epoch != 0 && s.epoch >= minEpoch, IndexNavGuardEpoch(s.epoch, minEpoch));

        uint256 supply = IERC20(src.shareToken(indexId)).totalSupply();
        if (supply != 0) {
            uint256 live = s.totalNav * 1e18 / supply;
            uint256 diff = live > s.navPerShare ? live - s.navPerShare : s.navPerShare - live;
            uint256 devBps = diff * AquaIndexArgs.BPS / s.navPerShare;
            require(devBps <= maxDeviationBps, IndexNavGuardDeviation(devBps, maxDeviationBps));
        }
    }
}
