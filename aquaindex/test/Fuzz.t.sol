// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Base } from "./Base.t.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { AquaIndexStrategyManager as SM } from "../contracts/swapvm/AquaIndexStrategyManager.sol";

contract FuzzTest is Base {
    ISwapVM.Order internal order;

    function _market(uint16 spread, uint16 slope) internal {
        SM.Params memory p = _strategy(SM.Kind.NAV_ANCHORED);
        p.spreadBps = spread;
        p.slopeBps = slope;
        p.maxAdjustBps = 2000;
        p.maxSkewBps = 9000;
        (order,) = _bootstrapMarket(p);
        vm.prank(alice);
        share.transfer(bob, 100e18);
    }

    function testFuzz_quoteEqualsSwap_exactIn_buy(uint256 amt, uint16 spread, uint16 slope) public {
        amt = bound(amt, 1e6, 20_000e6);
        spread = uint16(bound(spread, 0, 500));
        slope = uint16(bound(slope, 0, 10_000));
        _market(spread, slope);
        (uint256 qi, uint256 qo) = _quote(order, bob, address(usdc), address(share), amt, true);
        (uint256 si, uint256 so) = _swap(order, bob, address(usdc), address(share), amt, true);
        assertEq(qi, si);
        assertEq(qo, so);
    }

    function testFuzz_quoteEqualsSwap_exactOut_sell(uint256 outAmt, uint16 spread, uint16 slope) public {
        outAmt = bound(outAmt, 1e6, 5_000e6);
        spread = uint16(bound(spread, 0, 500));
        slope = uint16(bound(slope, 0, 10_000));
        _market(spread, slope);
        (uint256 qi, uint256 qo) = _quote(order, bob, address(share), address(usdc), outAmt, false);
        (uint256 si, uint256 so) = _swap(order, bob, address(share), address(usdc), outAmt, false);
        assertEq(qi, si);
        assertEq(qo, so);
    }

    /// buy then sell back everything bought: the taker can never end up with more USDC (spread>0)
    function testFuzz_roundTripNeverProfits(uint256 amt, uint16 slope) public {
        amt = bound(amt, 10e6, 20_000e6);
        slope = uint16(bound(slope, 0, 10_000));
        _market(20, slope);
        (, uint256 gotShares) = _swap(order, bob, address(usdc), address(share), amt, true);
        (, uint256 back) = _swap(order, bob, address(share), address(usdc), gotShares, true);
        assertLe(back, amt);
    }

    /// exact-out cost, paid exact-in, buys at least the requested shares (no free shares from rounding)
    function testFuzz_exactOutThenExactIn_consistent(uint256 shares) public {
        shares = bound(shares, 1e15, 40e18);
        _market(20, 0);
        (uint256 cost,) = _quote(order, bob, address(usdc), address(share), shares, false);
        (, uint256 out) = _quote(order, bob, address(usdc), address(share), cost, true);
        assertGe(out + 1e12, shares); // within one raw USDC unit of price
        assertLe(out, shares + 1e12);
    }

    /// the price per share for a buyer is non-decreasing in the maker's share scarcity (skew monotonicity)
    function testFuzz_skewMonotone(uint256 sharesA, uint256 sharesB) public {
        sharesA = bound(sharesA, 100e18, 900e18);
        sharesB = bound(sharesB, 100e18, 900e18);
        if (sharesA > sharesB) (sharesA, sharesB) = (sharesB, sharesA);
        _subscribe(alice, 100_000e6);
        _publish();
        uint256 oA = _out(sharesA, 1);
        uint256 oB = _out(sharesB, 2);
        // holding more shares (B) never makes shares more expensive than holding fewer (A)
        assertGe(oB + 1, oA);
    }

    function _out(uint256 shares, uint64 salt) internal returns (uint256 out) {
        SM.Params memory p = _strategy(SM.Kind.NAV_ANCHORED);
        p.salt = salt;
        p.slopeBps = 5000;
        p.maxAdjustBps = 2000;
        p.maxSkewBps = 10_000;
        (ISwapVM.Order memory o,) = sm.buildOrder(p);
        uint256 usdcAmt = (100_000e6 - shares * 100 / 1e18 * 1e6);
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        _ship(o, a, b, a == address(share) ? shares : usdcAmt, a == address(share) ? usdcAmt : shares);
        (, out) = _quote(o, bob, address(usdc), address(share), 500e6, true);
    }
}
