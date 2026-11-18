// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Base } from "./Base.t.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/contracts/libs/MakerTraits.sol";
import { Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";
import { XYCSwap } from "@1inch/swap-vm/contracts/instructions/XYCSwap.sol";
import { IndexRegistry } from "../contracts/index/IndexRegistry.sol";
import { RebalanceManager } from "../contracts/index/RebalanceManager.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";

contract RebalanceTest is Base {
    address internal dealer = vm.addr(201);

    function _xycOrder(address tA, address tB, uint64 salt) internal view returns (ISwapVM.Order memory) {
        (address a, address b) = tA < tB ? (tA, tB) : (tB, tA);
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: dealer,
                receiver: address(0),
                tokenA: a,
                tokenB: b,
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: false,
                hasPreTransferOutHook: false,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(0),
                postTransferInData: "",
                preTransferOutTarget: address(0),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: bytes.concat(Salt.build(salt), XYCSwap.build())
            })
        );
    }

    function _dealerShip(MockERC20 asset, uint256 assetAmt, uint256 usdcAmt) internal returns (ISwapVM.Order memory o) {
        o = _xycOrder(address(asset), address(usdc), uint64(uint160(address(asset))));
        asset.mint(dealer, assetAmt);
        usdc.mint(dealer, usdcAmt);
        vm.startPrank(dealer);
        asset.approve(address(aqua), type(uint256).max);
        usdc.approve(address(aqua), type(uint256).max);
        vm.stopPrank();
        (address a, address b) = address(asset) < address(usdc) ? (address(asset), address(usdc)) : (address(usdc), address(asset));
        _ship(o, a, b, a == address(asset) ? assetAmt : usdcAmt, a == address(asset) ? usdcAmt : assetAmt);
    }

    function test_drift_and_proposal_forIdleCash() public {
        _subscribe(alice, 100_000e6);
        (uint256 nav, RebalanceManager.AssetDrift[] memory d) = rebal.drift(idx);
        assertEq(nav, 100_000e18);
        assertEq(d.length, 6);
        // each constituent: current 0, target 20k, delta +20k; cash: current 100k, target 0
        for (uint256 i; i < 5; ++i) {
            assertEq(d[i].deltaValue, int256(20_000e18));
            assertEq(d[i].driftBps, -2000);
        }
        assertEq(d[5].driftBps, 10_000);
        RebalanceManager.TradeProposal[] memory t = rebal.propose(idx, 1e18);
        assertEq(t.length, 5);
        for (uint256 i; i < 5; ++i) {
            assertEq(t[i].sellAsset, address(usdc));
            assertEq(t[i].sellValue, 20_000e18);
            assertEq(t[i].sellAmount, 20_000e6);
        }
    }

    function test_execute_rebalance_throughAquaStrategies_reachesTargets() public {
        _subscribe(alice, 100_000e6);
        for (uint256 i; i < 5; ++i) {
            uint256 px = i == 0 ? 2500 : i == 1 ? 4000 : i == 2 ? 1600 : i == 3 ? 1500 : 1100;
            ISwapVM.Order memory o = _dealerShip(assets[i], 10_000e18, 10_000e18 * px / 1e12);
            bytes memory td = _takerData(address(rebal), address(usdc), address(assets[i]), true);
            (uint256 sold, uint256 bought) = rebal.execute(idx, address(usdc), address(assets[i]), 20_000e6, o, td, 0);
            assertEq(sold, 20_000e6);
            assertGt(bought, 0);
        }
        (uint256 nav, RebalanceManager.AssetDrift[] memory d) = rebal.drift(idx);
        assertApproxEqRel(nav, 100_000e18, 3e15); // value preserved up to curve slippage (< 0.3%)
        for (uint256 i; i < 5; ++i) {
            assertApproxEqAbs(d[i].driftBps, 0, 30);
        }
        assertLe(uint256(d[5].driftBps < 0 ? -d[5].driftBps : d[5].driftBps), 1);
        assertTrue(vault.verifyBacking());
        assertEq(usdc.balanceOf(address(rebal)), 0);
        assertEq(assets[0].balanceOf(address(rebal)), 0);
        assertEq(usdc.allowance(address(rebal), address(router)), 0);
        // dealer's virtual allocation was consumed through Aqua
        assertGt(assets[0].balanceOf(address(vault)), 0);
    }

    function test_execute_guards() public {
        _subscribe(alice, 100_000e6);
        ISwapVM.Order memory o = _dealerShip(assets[0], 10_000e18, 25_000_000e6);
        bytes memory td = _takerData(address(rebal), address(usdc), address(assets[0]), true);

        vm.prank(bob);
        vm.expectRevert();
        rebal.execute(idx, address(usdc), address(assets[0]), 1_000e6, o, td, 0); // no role

        vm.expectRevert(abi.encodeWithSelector(RebalanceManager.TradeTooLarge.selector, 30_000e18, 25_000e18));
        rebal.execute(idx, address(usdc), address(assets[0]), 30_000e6, o, td, 0);

        vm.expectRevert(); // min out not met
        rebal.execute(idx, address(usdc), address(assets[0]), 1_000e6, o, td, 1_000e18);

        vm.expectRevert(abi.encodeWithSelector(RebalanceManager.AssetNotAllowed.selector, address(0xBEEF)));
        rebal.execute(idx, address(usdc), address(0xBEEF), 1_000e6, o, td, 0);
    }

    function test_execute_badPrice_revertsOnSlippage() public {
        _subscribe(alice, 100_000e6);
        // dealer quotes mRELI at 3000 instead of the oracle's 2500 (20% worse for the vault)
        ISwapVM.Order memory o = _dealerShip(assets[0], 10_000e18, 30_000_000e6);
        bytes memory td = _takerData(address(rebal), address(usdc), address(assets[0]), true);
        vm.expectRevert();
        rebal.execute(idx, address(usdc), address(assets[0]), 10_000e6, o, td, 0);
        assertEq(vault.holdings(address(usdc)), 100_000e6); // state fully reverted
    }

    function test_execute_cannotIncreaseDrift() public {
        _subscribe(alice, 100_000e6);
        ISwapVM.Order memory o = _dealerShip(assets[0], 10_000e18, 25_000_000e6);
        bytes memory td = _takerData(address(rebal), address(usdc), address(assets[0]), true);
        rebal.execute(idx, address(usdc), address(assets[0]), 24_000e6, o, td, 0);
        rebal.execute(idx, address(usdc), address(assets[0]), 24_000e6, o, td, 0);
        rebal.execute(idx, address(usdc), address(assets[0]), 24_000e6, o, td, 0);
        // cash 28k, mRELI 72k: another buy would push mRELI drift above the current maximum
        vm.expectRevert(RebalanceManager.DriftNotImproved.selector);
        rebal.execute(idx, address(usdc), address(assets[0]), 24_000e6, o, td, 0);
    }

    function test_execute_pausedIndexBlocked() public {
        _subscribe(alice, 100_000e6);
        ISwapVM.Order memory o = _dealerShip(assets[0], 10_000e18, 25_000_000e6);
        bytes memory td = _takerData(address(rebal), address(usdc), address(assets[0]), true);
        registry.setStatus(idx, IndexRegistry.Status.PAUSED);
        vm.expectRevert();
        rebal.execute(idx, address(usdc), address(assets[0]), 1_000e6, o, td, 0);
    }
}

