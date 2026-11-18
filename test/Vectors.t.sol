// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Test, stdJson } from "forge-std/Test.sol";
import { Deadline, Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";
import { XYCSwap } from "@1inch/swap-vm/contracts/instructions/XYCSwap.sol";
import { FeeFlatIn } from "@1inch/swap-vm/contracts/instructions/FeeFlat.sol";
import { Jump, JumpIfTokenIn, JumpIfTokenOut } from "@1inch/swap-vm/contracts/instructions/Jumps.sol";
import { XYCConcentrateSwap } from "@1inch/swap-vm/contracts/instructions/XYCConcentrate.sol";

import { AquaIndexStrategyManager as SM } from "../contracts/swapvm/AquaIndexStrategyManager.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { MakerTraits } from "@1inch/swap-vm/contracts/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/contracts/libs/TakerTraits.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { IndexNavGuard } from "../contracts/swapvm/instructions/IndexNavGuard.sol";
import { IndexMaxTrade } from "../contracts/swapvm/instructions/IndexMaxTrade.sol";
import { IndexCapabilityGuard } from "../contracts/swapvm/instructions/IndexCapabilityGuard.sol";
import { IndexNavPriceAdjuster } from "../contracts/swapvm/instructions/IndexNavPriceAdjuster.sol";
import { IndexInventorySkew } from "../contracts/swapvm/instructions/IndexInventorySkew.sol";

/// @notice Cross-language compatibility: the Solidity side writes `golden.json` (opcode ids + program bytes for fixed
///         parameters) which the TypeScript SDK tests compare against; and it reads `ts-vectors.json`, produced by the
///         SDK builder from the same parameters, asserting byte equality with `AquaIndexStrategyManager.buildProgram`.
contract VectorsTest is Test {
    using stdJson for string;

    string internal constant OUT = "packages/aquaindex-swapvm-sdk/test/golden.json";
    string internal constant TS = "packages/aquaindex-swapvm-sdk/test/ts-vectors.json";

    function _params(SM.Kind kind) internal pure returns (SM.Params memory p) {
        p.kind = kind;
        p.maker = address(0x1111111111111111111111111111111111111111);
        p.navSource = address(0x2222222222222222222222222222222222222222);
        p.indexId = 7;
        p.indexToken = address(0x3333333333333333333333333333333333333333);
        p.quoteToken = address(0x4444444444444444444444444444444444444444);
        p.expiry = 1_900_000_000;
        p.salt = 42;
        p.maxNavAge = 300;
        p.minEpoch = 3;
        p.maxNavDeviationBps = 150;
        p.premiumBps = -125;
        p.maxPremiumBps = 300;
        p.maxDiscountBps = 250;
        p.spreadBps = 20;
        p.feeBps = 5;
        p.targetShareBps = 5000;
        p.maxSkewBps = 3000;
        p.slopeBps = 5000;
        p.maxAdjustBps = 500;
        p.maxAmountIn = 1_000_000e6;
        p.maxAmountOut = 5_000e18;
        p.minLiquidityOut = 10e18;
        p.capabilityRegistry = address(0x5555555555555555555555555555555555555555);
        p.capabilityId = bytes32(uint256(0xabcdef));
    }

    function _kindName(SM.Kind k) internal pure returns (string memory) {
        return k == SM.Kind.NAV_ANCHORED ? "A" : k == SM.Kind.CONSERVATIVE ? "B" : "C";
    }

    function test_writeGolden() public {
        SM sm = new SM(IAqua(address(0)), address(0));
        string memory root = "g";
        root.serialize("instructionSetVersion", uint256(1));
        string memory ops = "ops";
        ops.serialize("Salt", uint256(Salt.opcode.asU8()));
        ops.serialize("Deadline", uint256(Deadline.opcode.asU8()));
        ops.serialize("Jump", uint256(Jump.opcode.asU8()));
        ops.serialize("JumpIfTokenIn", uint256(JumpIfTokenIn.opcode.asU8()));
        ops.serialize("JumpIfTokenOut", uint256(JumpIfTokenOut.opcode.asU8()));
        ops.serialize("XYCSwap", uint256(XYCSwap.opcode.asU8()));
        ops.serialize("XYCConcentrateSwap", uint256(XYCConcentrateSwap.opcode.asU8()));
        ops.serialize("FeeFlatIn", uint256(FeeFlatIn.opcode.asU8()));
        ops.serialize("IndexNavGuard", uint256(IndexNavGuard.opcode.asU8()));
        ops.serialize("IndexNavPriceAdjuster", uint256(IndexNavPriceAdjuster.opcode.asU8()));
        ops.serialize("IndexInventorySkew", uint256(IndexInventorySkew.opcode.asU8()));
        ops.serialize("IndexMaxTrade", uint256(IndexMaxTrade.opcode.asU8()));
        string memory opsOut = ops.serialize("IndexCapabilityGuard", uint256(IndexCapabilityGuard.opcode.asU8()));
        root.serialize("opcodes", opsOut);

        string memory progs = "progs";
        string memory progsOut;
        for (uint256 i; i < 3; ++i) {
            SM.Kind k = SM.Kind(i);
            progsOut = progs.serialize(_kindName(k), sm.buildProgram(_params(k)));
        }
        root.serialize("programs", progsOut);
        string memory ords = "ords";
        string memory ordsOut;
        for (uint256 i; i < 3; ++i) {
            SM.Kind k = SM.Kind(i);
            (ISwapVM.Order memory o, bytes32 h) = sm.buildOrder(_params(k));
            string memory one = string.concat("ord", _kindName(k));
            one.serialize("maker", o.maker);
            one.serialize("traits", uint256(MakerTraits.unwrap(o.traits)));
            one.serialize("data", o.data);
            string memory oneOut = one.serialize("hash", h);
            ordsOut = ords.serialize(_kindName(k), oneOut);
        }
        root.serialize("orders", ordsOut);
        string memory tk = "tk";
        string memory tkOut;
        for (uint256 i; i < 4; ++i) {
            TakerTraitsLib.Args memory a;
            a.isExactIn = i & 1 != 0;
            a.isAToB = i & 2 != 0;
            a.useTransferFromAndAquaPush = true;
            a.threshold = abi.encode(uint256(123456 + i));
            tkOut = tk.serialize(string.concat("c", vm.toString(i)), TakerTraitsLib.build(a));
        }
        root.serialize("takerData", tkOut);
        string memory ixs = "ixs";
        ixs.serialize("navGuard", IndexNavGuard.build(address(0x2222222222222222222222222222222222222222), 7, 300, 3, 150));
        ixs.serialize("maxTrade", IndexMaxTrade.build(address(0x2222222222222222222222222222222222222222), 7, 1, 2, 3));
        string memory ixsOut = ixs.serialize("capability", IndexCapabilityGuard.build(address(0x5555555555555555555555555555555555555555), bytes32(uint256(0xabcdef))));
        string memory finalJson = root.serialize("instructions", ixsOut);
        vm.writeJson(finalJson, OUT);
    }

    /// Runs after the TS vectors exist (skipped otherwise): TS builder output == Solidity builder output.
    function test_tsVectorsMatchSolidity() public {
        if (!vm.exists(TS)) {
            vm.skip(true);
        }
        string memory json = vm.readFile(TS);
        SM sm = new SM(IAqua(address(0)), address(0));
        for (uint256 i; i < 3; ++i) {
            SM.Kind k = SM.Kind(i);
            bytes memory tsProg = json.readBytes(string.concat(".programs.", _kindName(k)));
            assertEq(tsProg, sm.buildProgram(_params(k)), string.concat("program mismatch for strategy ", _kindName(k)));
            (ISwapVM.Order memory o, bytes32 h) = sm.buildOrder(_params(k));
            string memory base = string.concat(".orders.", _kindName(k));
            assertEq(json.readBytes(string.concat(base, ".data")), o.data, "order data");
            assertEq(json.readUint(string.concat(base, ".traits")), uint256(MakerTraits.unwrap(o.traits)), "traits");
            assertEq(json.readBytes32(string.concat(base, ".hash")), h, "order hash");
        }
    }
}
