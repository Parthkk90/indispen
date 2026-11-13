// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Base } from "./Base.t.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/contracts/libs/MakerTraits.sol";
import { Deadline, Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";

import { AquaIndexStrategyManager as SM } from "../contracts/swapvm/AquaIndexStrategyManager.sol";
import { IndexRegistry } from "../contracts/index/IndexRegistry.sol";
import { IndexNavGuard } from "../contracts/swapvm/instructions/IndexNavGuard.sol";
import { IndexNavPriceAdjuster } from "../contracts/swapvm/instructions/IndexNavPriceAdjuster.sol";
import { IndexInventorySkew } from "../contracts/swapvm/instructions/IndexInventorySkew.sol";
import { IndexMaxTrade } from "../contracts/swapvm/instructions/IndexMaxTrade.sol";
import { IndexCapabilityGuard } from "../contracts/swapvm/instructions/IndexCapabilityGuard.sol";
import { AquaIndexOpcodes } from "../contracts/swapvm/opcodes/AquaIndexOpcodes.sol";
import { AquaIndexArgs } from "../contracts/swapvm/instructions/AquaIndexArgs.sol";

contract OpcodesTest is Base {
    SM.Params internal p;
    uint16 internal adjCap = 2000;
    ISwapVM.Order internal order;
    bytes32 internal hash;

    function _setup(SM.Kind kind) internal {
        p = _strategy(kind);
        (order, hash) = _bootstrapMarket(p);
    }

    // ------------------------------------------------------------------ opcode table
    function test_opcodeIds() public pure {
        assertEq(IndexNavGuard.opcode.asU8(), 0xe0);
        assertEq(IndexNavPriceAdjuster.opcode.asU8(), 0xe1);
        assertEq(IndexInventorySkew.opcode.asU8(), 0xe2);
        assertEq(IndexMaxTrade.opcode.asU8(), 0xe3);
        assertEq(IndexCapabilityGuard.opcode.asU8(), 0xe4);
        assertEq(Deadline.opcode.asU8(), 0x20);
        assertEq(Salt.opcode.asU8(), 0x02);
    }

    function test_builderHeaders_matchOpcodesAndLengths() public view {
        bytes memory g = IndexNavGuard.build(address(oracle), 1, 300, 1, 100);
        assertEq(uint8(g[0]), 0xe0);
        assertEq(uint8(g[1]), 42);
        assertEq(g.length, 44);
        bytes memory m = IndexMaxTrade.build(address(oracle), 1, 1, 2, 3);
        assertEq(uint8(m[0]), 0xe3);
        assertEq(uint8(m[1]), 76);
        bytes memory c = IndexCapabilityGuard.build(address(caps), bytes32(uint256(7)));
        assertEq(uint8(c[0]), 0xe4);
        assertEq(uint8(c[1]), 52);
        assertEq(sm.INSTRUCTION_SET_VERSION(), 1);
    }

    // ------------------------------------------------------------------ pricing
    function _ask() internal pure returns (uint256) {
        return uint256(100e18) * 10_020 / 10_000; // 100.2 USDC per share
    }

    function test_navPrice_buyExactIn_matchesFormula_and_settlesThroughAqua() public {
        _setup(SM.Kind.NAV_ANCHORED);
        uint256 amountIn = 1000e6;
        uint256 expectedOut = amountIn * 1e18 * 1e18 / (_ask() * 1e6);
        (uint256 qIn, uint256 qOut) = _quote(order, bob, address(usdc), address(share), amountIn, true);
        assertEq(qIn, amountIn);
        assertEq(qOut, expectedOut);

        uint256 bobShares = share.balanceOf(bob);
        uint256 aliceUsdc = usdc.balanceOf(alice);
        uint256 aliceShares = share.balanceOf(alice);
        (uint256 sIn, uint256 sOut) = _swap(order, bob, address(usdc), address(share), amountIn, true);
        assertEq(sIn, qIn, "quote == swap in");
        assertEq(sOut, qOut, "quote == swap out");
        assertEq(share.balanceOf(bob) - bobShares, sOut);
        assertEq(usdc.balanceOf(alice) - aliceUsdc, sIn); // pushed to maker wallet
        assertEq(aliceShares - share.balanceOf(alice), sOut); // pulled from maker wallet

        (uint256 bs, uint256 bq) = sm.balances(alice, hash, address(share), address(usdc));
        assertEq(bs, 500e18 - sOut);
        assertEq(bq, 50_000e6 + sIn);
        assertTrue(vault.verifyBacking());
    }

    function test_navPrice_sellExactIn_bid() public {
        _setup(SM.Kind.NAV_ANCHORED);
        vm.prank(alice);
        share.transfer(bob, 100e18);
        uint256 bid = uint256(100e18) * 9_980 / 10_000;
        uint256 amountIn = 10e18;
        uint256 expected = amountIn * (bid * 1e6) / (1e18 * 1e18);
        (, uint256 out) = _quote(order, bob, address(share), address(usdc), amountIn, true);
        assertEq(out, expected);
        (, uint256 sOut) = _swap(order, bob, address(share), address(usdc), amountIn, true);
        assertEq(sOut, out);
    }

    function test_navPrice_exactOut_quoteEqualsSwap_and_roundsForMaker() public {
        _setup(SM.Kind.NAV_ANCHORED);
        uint256 want = 7e18;
        (uint256 qIn, uint256 qOut) = _quote(order, bob, address(usdc), address(share), want, false);
        assertEq(qOut, want);
        uint256 exact = want * _ask() / 1e18 / 1e12; // floor of true cost in raw USDC
        assertGe(qIn, exact); // never below the exact cost
        assertLe(qIn, exact + 1);
        (uint256 sIn, uint256 sOut) = _swap(order, bob, address(usdc), address(share), want, false);
        assertEq(sIn, qIn);
        assertEq(sOut, want);
    }

    function test_navPrice_roundTrip_neverProfitableForTaker() public {
        p = _strategy(SM.Kind.NAV_ANCHORED);
        p.slopeBps = 5000; // skew enabled: impact is priced at post-trade inventory
        p.maxAdjustBps = 2000;
        (order, hash) = _bootstrapMarket(p);
        (, uint256 gotShares) = _swap(order, bob, address(usdc), address(share), 5_000e6, true);
        (, uint256 backUsdc) = _swap(order, bob, address(share), address(usdc), gotShares, true);
        assertLt(backUsdc, 5_000e6);
    }

    function test_navChange_changesQuote() public {
        _setup(SM.Kind.NAV_ANCHORED);
        (, uint256 out1) = _quote(order, bob, address(usdc), address(share), 1000e6, true);
        // give the vault holdings that move with price, then re-price and republish
        vm.startPrank(address(subs));
        assets[0].mint(address(vault), 20e18);
        vault.recordDeposit(address(assets[0]), 20e18);
        vm.stopPrank();
        oracle.setPrice(address(assets[0]), 3000e18);
        _publish(); // nav = 100k + 60k = 160k, supply 1000 -> 160/share
        (, uint256 out2) = _quote(order, bob, address(usdc), address(share), 1000e6, true);
        assertLt(out2, out1);
        assertApproxEqRel(out2 * 160, out1 * 100, 1e15);
    }

    function test_premium_outOfBounds_rejectedAtBuild() public {
        p = _strategy(SM.Kind.NAV_ANCHORED);
        p.premiumBps = 301;
        vm.expectRevert();
        sm.buildProgram(p);
        p.premiumBps = -301;
        vm.expectRevert();
        sm.buildProgram(p);
        p.premiumBps = -300;
        sm.buildProgram(p);
    }

    function test_premium_shiftsPrice() public {
        p = _strategy(SM.Kind.NAV_ANCHORED);
        p.premiumBps = 200;
        (order, hash) = _bootstrapMarket(p);
        uint256 ask = uint256(100e18) * 10_200 / 10_000 * 10_020 / 10_000;
        (, uint256 out) = _quote(order, bob, address(usdc), address(share), 1000e6, true);
        assertApproxEqAbs(out, 1000e18 * 1e18 / ask, 2);
    }

    function test_wrongTokenPair_rejected() public {
        _setup(SM.Kind.NAV_ANCHORED);
        bytes memory td = _takerData(bob, address(assets[0]), address(share), true);
        vm.prank(bob);
        vm.expectRevert();
        router.quote(order, 1e18, td);
    }

    // ------------------------------------------------------------------ NAV guard
    function test_navGuard_stale_reverts() public {
        _setup(SM.Kind.NAV_ANCHORED);
        vm.warp(block.timestamp + 30 minutes); // max age 5 min
        oracle.setPrice(address(usdc), 1e18); // keep price book fresh; the NAV snapshot is the stale part
        bytes memory td = _takerData(bob, address(usdc), address(share), true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IndexNavGuard.IndexNavGuardStale.selector, 30 minutes, uint32(5 minutes)));
        router.quote(order, 1000e6, td);
        _publish();
        _quote(order, bob, address(usdc), address(share), 1000e6, true);
    }

    function test_navGuard_noSnapshot_reverts() public {
        _subscribe(alice, 100_000e6); // never published
        p = _strategy(SM.Kind.NAV_ANCHORED);
        (order, hash) = sm.buildOrder(p);
        _shipDefault();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IndexNavGuard.IndexNavGuardNoSnapshot.selector, idx));
        router.quote(order, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function test_navGuard_epochTooLow_reverts() public {
        p = _strategy(SM.Kind.NAV_ANCHORED);
        p.minEpoch = 5;
        (order, hash) = _bootstrapMarket(p);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IndexNavGuard.IndexNavGuardEpoch.selector, uint64(1), uint64(5)));
        router.quote(order, 1000e6, _takerData(bob, address(usdc), address(share), true));
        _publish();
        _publish();
        _publish();
        _publish();
        _quote(order, bob, address(usdc), address(share), 1000e6, true);
    }

    function test_navGuard_supplyMovedAfterPublish_deviation() public {
        _setup(SM.Kind.NAV_ANCHORED);
        // a mint after publish changes live nav/supply only if holdings differ; mint shares w/o backing is impossible,
        // so move the vault value: withdraw cash as manager (models an unpublished loss)
        vm.prank(address(subs));
        vault.withdraw(address(usdc), address(0xBEEF), 10_000e6);
        // live NAV/supply is unchanged in the snapshot (stale totals), supplyRef equals current supply -> no deviation
        _quote(order, bob, address(usdc), address(share), 1000e6, true);
        // now supply changes: bob subscribes -> supply 1500e18 vs snapshot total 100k
        _subscribe(bob, 50_000e6);
        vm.prank(bob);
        vm.expectRevert();
        router.quote(order, 1000e6, _takerData(bob, address(usdc), address(share), true));
        _publish();
        _quote(order, bob, address(usdc), address(share), 1000e6, true);
    }

    function test_navGuard_pausedIndex_reverts() public {
        _setup(SM.Kind.NAV_ANCHORED);
        registry.setStatus(idx, IndexRegistry.Status.PAUSED);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IndexNavGuard.IndexNavGuardInactive.selector, idx));
        router.quote(order, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function test_untrustedSource_rejected() public {
        router.setTrustedSource(address(oracle), false);
        p = _strategy(SM.Kind.NAV_ANCHORED);
        _subscribe(alice, 100_000e6);
        _publish();
        (order, hash) = sm.buildOrder(p);
        _shipDefault();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AquaIndexArgs.AquaIndexUntrustedSource.selector, address(oracle)));
        router.quote(order, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function _shipDefault() internal {
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        _ship(order, a, b, a == address(share) ? 500e18 : 50_000e6, a == address(share) ? 50_000e6 : 500e18);
    }

    // ------------------------------------------------------------------ max trade
    function test_maxTrade_inAmount_and_outAmount() public {
        p = _strategy(SM.Kind.CONSERVATIVE);
        p.maxAmountIn = 2_000e6;
        (order, hash) = _bootstrapMarket(p);
        _quote(order, bob, address(usdc), address(share), 2_000e6, true); // boundary OK
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IndexMaxTrade.IndexMaxTradeInAmount.selector, 2_000e6 + 1, uint128(2_000e6)));
        router.quote(order, 2_000e6 + 1, _takerData(bob, address(usdc), address(share), true));
    }

    function test_maxTrade_outCap_and_minLiquidity() public {
        p = _strategy(SM.Kind.NAV_ANCHORED);
        p.maxAmountOut = 5e18;
        p.minLiquidityOut = 495e18;
        (order, hash) = _bootstrapMarket(p);
        _quote(order, bob, address(usdc), address(share), 100e6, true);
        vm.prank(bob);
        vm.expectRevert(); // out > 5 shares
        router.quote(order, 600e6, _takerData(bob, address(usdc), address(share), true));
    }

    function test_maxTrade_minLiquidity() public {
        p = _strategy(SM.Kind.NAV_ANCHORED);
        p.minLiquidityOut = 497e18; // 500 - 497 = max 3 shares out
        (order, hash) = _bootstrapMarket(p);
        _quote(order, bob, address(usdc), address(share), 100e6, true);
        vm.prank(bob);
        vm.expectRevert();
        router.quote(order, 500e6, _takerData(bob, address(usdc), address(share), true));
    }

    function test_maxTrade_cannotExceedLiquidity() public {
        _setup(SM.Kind.NAV_ANCHORED);
        // asks for more shares than the strategy holds
        vm.prank(bob);
        vm.expectRevert();
        router.quote(order, 600e18, _takerData(bob, address(usdc), address(share), false));
    }

    function test_zeroAmount_rejected() public {
        _setup(SM.Kind.NAV_ANCHORED);
        vm.prank(bob);
        vm.expectRevert();
        router.quote(order, 0, _takerData(bob, address(usdc), address(share), true));
    }

    // ------------------------------------------------------------------ inventory skew
    function _quoteWithInventory(uint256 shares, uint256 usdcAmt, uint64 salt) internal returns (uint256 out) {
        SM.Params memory q = _strategy(SM.Kind.NAV_ANCHORED);
        q.salt = salt;
        q.slopeBps = 5000;
        q.maxAdjustBps = adjCap;
        (ISwapVM.Order memory o,) = sm.buildOrder(q);
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        _ship(o, a, b, a == address(share) ? shares : usdcAmt, a == address(share) ? usdcAmt : shares);
        (, out) = _quote(o, bob, address(usdc), address(share), 1000e6, true);
    }

    function test_skew_longShares_cheaperToBuy_and_monotone() public {
        _subscribe(alice, 100_000e6);
        _publish();
        // share value fractions: 50%, 60%, 70%, 80% (with $ values)
        uint256 o50 = _quoteWithInventory(500e18, 50_000e6, 11);
        uint256 o60 = _quoteWithInventory(600e18, 40_000e6, 12);
        uint256 o70 = _quoteWithInventory(700e18, 30_000e6, 13);
        uint256 o80 = _quoteWithInventory(800e18, 20_000e6, 14);
        assertLt(o50, o60);
        assertLt(o60, o70);
        assertLt(o70, o80); // more shares held -> more shares per USDC for taker
        // short on shares -> worse for buyers than balanced
        uint256 o30 = _quoteWithInventory(300e18, 70_000e6, 15);
        assertGt(o50, o30);
    }

    function test_skew_cappedByMaxAdjust() public {
        adjCap = 500;
        _subscribe(alice, 100_000e6);
        _publish();
        uint256 o90 = _quoteWithInventory(900e18, 10_000e6, 21); // imbalance 4000 bps -> capped at 500 bps
        uint256 unskewed = 1000e6 * 1e18 * 1e18 / (_ask() * 1e6);
        assertLe(o90, unskewed * 10_000 / 9_500 + 1); // never more than +500 bps for the taker
        assertGe(o90, unskewed * 10_000 / 9_500 - 1); // and the cap is reached at 40% imbalance
    }

    function test_skew_maxSkew_blocksWorseningTrade() public {
        p = _strategy(SM.Kind.NAV_ANCHORED);
        p.maxSkewBps = 1000; // allow only +-10% around 50%
        _subscribe(alice, 100_000e6);
        _publish();
        (order, hash) = sm.buildOrder(p);
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        // maker starts at 58% shares (within band): $58k shares, $42k usdc
        _ship(order, a, b, a == address(share) ? 580e18 : 42_000e6, a == address(share) ? 42_000e6 : 580e18);
        // taker sells shares to the maker -> maker gets even longer; pushes past 60% -> revert
        vm.prank(alice);
        share.transfer(bob, 200e18);
        vm.prank(bob);
        vm.expectRevert();
        router.quote(order, 100e18, _takerData(bob, address(share), address(usdc), true));
        // taker buys shares -> imbalance shrinks -> allowed
        _quote(order, bob, address(usdc), address(share), 5_000e6, true);
    }

    function test_skew_depletedInventory_reverts() public {
        _subscribe(alice, 100_000e6);
        _publish();
        SM.Params memory q = _strategy(SM.Kind.NAV_ANCHORED);
        q.salt = 99;
        (ISwapVM.Order memory o,) = sm.buildOrder(q);
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        _ship(o, a, b, 0, 0);
        vm.prank(bob);
        vm.expectRevert(IndexInventorySkew.IndexSkewDepletedInventory.selector);
        router.quote(o, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function test_skew_usesAquaVirtualBalances_notWallet() public {
        _setup(SM.Kind.NAV_ANCHORED);
        uint256 out1;
        (, out1) = _quote(order, bob, address(usdc), address(share), 1000e6, true);
        // alice's wallet shares change; Aqua virtual balances do not -> same quote
        vm.prank(alice);
        share.transfer(carol, 100e18);
        (, uint256 out2) = _quote(order, bob, address(usdc), address(share), 1000e6, true);
        assertEq(out1, out2);
    }

    // ------------------------------------------------------------------ capability guard
    function _capStrategy(bytes32 id) internal returns (SM.Params memory q) {
        q = _strategy(SM.Kind.NAV_ANCHORED);
        q.capabilityRegistry = address(caps);
        q.capabilityId = id;
        _subscribe(alice, 100_000e6);
        _publish();
        (order, hash) = sm.buildOrder(q);
        _shipDefault();
    }

    function _issue(address op, uint128 max, uint40 expiry) internal returns (bytes32) {
        vm.prank(alice);
        return caps.issue(op, idx, address(share), address(usdc), max, expiry);
    }

    function test_capability_authorizedOperator_ok_unauthorized_rejected() public {
        bytes32 id = _issue(carol, 5_000e6, uint40(block.timestamp + 1 days));
        _capStrategy(id);
        _quote(order, carol, address(usdc), address(share), 1000e6, true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IndexCapabilityGuard.IndexCapabilityUnauthorizedOperator.selector, bob, carol));
        router.quote(order, 1000e6, _takerData(bob, address(usdc), address(share), true));
        _swap(order, carol, address(usdc), address(share), 1000e6, true);
    }

    function test_capability_amountCap_expiry_revoked_nonce() public {
        bytes32 id = _issue(carol, 1_000e6, uint40(block.timestamp + 1 days));
        _capStrategy(id);
        _quote(order, carol, address(usdc), address(share), 1000e6, true);
        vm.prank(carol);
        vm.expectRevert();
        router.quote(order, 1000e6 + 1, _takerData(carol, address(usdc), address(share), true));

        // keep NAV fresh while warping
        vm.warp(block.timestamp + 2 days);
        oracle.setPrice(address(usdc), 1e18);
        _publish();
        vm.prank(carol);
        vm.expectRevert();
        router.quote(order, 100e6, _takerData(carol, address(usdc), address(share), true));
    }

    function test_capability_revoked_and_nonceBump() public {
        bytes32 id = _issue(carol, 5_000e6, uint40(block.timestamp + 1 days));
        _capStrategy(id);
        _quote(order, carol, address(usdc), address(share), 100e6, true);
        vm.prank(alice);
        caps.revoke(id);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IndexCapabilityGuard.IndexCapabilityRevoked.selector, id));
        router.quote(order, 100e6, _takerData(carol, address(usdc), address(share), true));

        // nonce bump invalidates old capabilities of the maker
        bytes32 id2 = _issue(carol, 5_000e6, uint40(block.timestamp + 1 days));
        SM.Params memory q = _strategy(SM.Kind.NAV_ANCHORED);
        q.capabilityRegistry = address(caps);
        q.capabilityId = id2;
        q.salt = 2;
        (order, hash) = sm.buildOrder(q);
        _shipDefault();
        _quote(order, carol, address(usdc), address(share), 100e6, true);
        vm.prank(alice);
        caps.bumpMinNonce();
        vm.prank(carol);
        vm.expectRevert();
        router.quote(order, 100e6, _takerData(carol, address(usdc), address(share), true));
    }

    function test_capability_onlyGrantorCanRevoke_and_wrongPair() public {
        bytes32 id = _issue(carol, 5_000e6, uint40(block.timestamp + 1 days));
        vm.prank(bob);
        vm.expectRevert();
        caps.revoke(id);
        // capability scoped to a different pair
        vm.prank(alice);
        bytes32 id2 = caps.issue(carol, idx, address(assets[0]), address(usdc), 5_000e6, uint40(block.timestamp + 1 days));
        _capStrategy(id2);
        vm.prank(carol);
        vm.expectRevert();
        router.quote(order, 100e6, _takerData(carol, address(usdc), address(share), true));
    }

    function test_capability_makerMismatch() public {
        // capability granted by bob cannot authorise trades on alice's strategy
        vm.prank(bob);
        bytes32 id = caps.issue(carol, idx, address(share), address(usdc), 5_000e6, uint40(block.timestamp + 1 days));
        _capStrategy(id);
        vm.prank(carol);
        vm.expectRevert();
        router.quote(order, 100e6, _takerData(carol, address(usdc), address(share), true));
    }

    // ------------------------------------------------------------------ malformed bytecode
    function _customOrder(bytes memory program) internal view returns (ISwapVM.Order memory o) {
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        o = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: alice,
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
                program: program
            })
        );
    }

    function test_unknownOpcode_reverts() public {
        _subscribe(alice, 100_000e6);
        ISwapVM.Order memory o = _customOrder(hex"e500");
        _shipOrder(o);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AquaIndexOpcodes.UnknownOpcode.selector, 0xe5));
        router.quote(o, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function test_upstreamOpcodeNotInSet_reverts() public {
        _subscribe(alice, 100_000e6);
        ISwapVM.Order memory o = _customOrder(hex"b200"); // OraclePriceAdjuster: not part of instruction set v1
        _shipOrder(o);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AquaIndexOpcodes.UnknownOpcode.selector, 0xb2));
        router.quote(o, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function test_malformedArgsLength_reverts() public {
        _subscribe(alice, 100_000e6);
        ISwapVM.Order memory o = _customOrder(abi.encodePacked(uint8(0xe0), uint8(3), hex"010203"));
        _shipOrder(o);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AquaIndexArgs.AquaIndexBadArgsLength.selector, 42, 3));
        router.quote(o, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function _shipOrder(ISwapVM.Order memory o) internal {
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        _ship(o, a, b, 1e18, 1e6);
    }

    // ------------------------------------------------------------------ lifecycle / isolation
    function test_dock_stopsExecution_andStrategiesImmutable() public {
        _setup(SM.Kind.NAV_ANCHORED);
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        vm.prank(alice);
        vm.expectRevert(); // same strategy cannot be shipped twice
        aqua.ship(address(router), abi.encode(order), _t(a, b), _amts(1, 1));
        vm.prank(alice);
        aqua.dock(address(router), hash, _t(a, b));
        vm.prank(bob);
        vm.expectRevert();
        router.quote(order, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function _t(address a, address b) internal pure returns (address[] memory t) {
        t = new address[](2);
        t[0] = a;
        t[1] = b;
    }

    function _amts(uint256 a, uint256 b) internal pure returns (uint256[] memory t) {
        t = new uint256[](2);
        t[0] = a;
        t[1] = b;
    }

    function test_depletedStrategy_cannotExecute() public {
        _setup(SM.Kind.NAV_ANCHORED);
        vm.prank(bob);
        vm.expectRevert();
        router.swap(order, 80_000e6, _takerData(bob, address(usdc), address(share), true)); // needs ~800 shares > 500
    }

    function test_strategyOnOtherApp_notUsable() public {
        // ship the same order to a DIFFERENT app address: the router reads balances for itself only
        _subscribe(alice, 100_000e6);
        _publish();
        (order, hash) = sm.buildOrder(_strategy(SM.Kind.NAV_ANCHORED));
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        vm.prank(alice);
        aqua.ship(address(0xA11CE), abi.encode(order), _t(a, b), _amts(500e18, 50_000e6));
        vm.prank(bob);
        vm.expectRevert();
        router.quote(order, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function test_vaultAssetsUntouchedBySwaps() public {
        _setup(SM.Kind.NAV_ANCHORED);
        uint256 vUsdc = usdc.balanceOf(address(vault));
        _swap(order, bob, address(usdc), address(share), 2_000e6, true);
        assertEq(usdc.balanceOf(address(vault)), vUsdc);
        assertEq(vault.holdings(address(usdc)), vUsdc);
        assertEq(share.totalSupply(), 1000e18); // swaps never mint
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(share.balanceOf(address(router)), 0);
    }

    // ------------------------------------------------------------------ strategies B and C
    function test_strategyB_conservative_widerSpread() public {
        p = _strategy(SM.Kind.CONSERVATIVE);
        p.spreadBps = 60;
        p.maxNavAge = 60;
        p.maxNavDeviationBps = 25;
        p.maxAmountIn = 5_000e6;
        (order, hash) = _bootstrapMarket(p);
        (, uint256 out) = _quote(order, bob, address(usdc), address(share), 1000e6, true);
        assertEq(out, 1000e6 * 1e18 * 1e18 / ((uint256(100e18) * 10_060 / 10_000) * 1e6));
        vm.warp(block.timestamp + 61);
        oracle.setPrice(address(usdc), 1e18);
        vm.prank(bob);
        vm.expectRevert();
        router.quote(order, 1000e6, _takerData(bob, address(usdc), address(share), true));
    }

    function test_strategyC_adaptive_xycCurveCappedByNav() public {
        p = _strategy(SM.Kind.ADAPTIVE);
        (order, hash) = _bootstrapMarket(p);
        // XYC price at the ship ratio is 100 USDC/share, pre-impact. NAV cap with spread keeps taker <= nav price
        uint256 amountIn = 1_000e6;
        (, uint256 out) = _quote(order, bob, address(usdc), address(share), amountIn, true);
        uint256 navOut = amountIn * 1e18 * 1e18 / (_ask() * 1e6);
        assertLe(out, navOut);
        assertGt(out, 0);
        (uint256 sIn, uint256 sOut) = _swap(order, bob, address(usdc), address(share), amountIn, true);
        assertEq(sOut, out);
        assertEq(sIn, amountIn);
        // if NAV moves up sharply the cap lowers the quote even though the curve is unchanged
        vm.startPrank(address(subs));
        assets[0].mint(address(vault), 20e18);
        vault.recordDeposit(address(assets[0]), 20e18);
        vm.stopPrank();
        oracle.setPrice(address(assets[0]), 3000e18);
        _publish();
        (, uint256 out2) = _quote(order, bob, address(usdc), address(share), amountIn, true);
        assertLt(out2, out);
    }

    // ------------------------------------------------------------------ strategy manager
    function test_strategyManager_registerAndDock() public {
        _setup(SM.Kind.NAV_ANCHORED);
        vm.prank(alice);
        bytes32 h = sm.register(p);
        assertEq(h, hash);
        (,, SM.Status st, uint32 ver,,) = sm.records(h);
        assertEq(uint8(st), 1);
        assertEq(ver, 1);

        vm.prank(bob);
        vm.expectRevert();
        sm.register(p); // not the maker

        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        vm.prank(alice);
        vm.expectRevert();
        sm.markDocked(h); // not docked yet
        vm.prank(alice);
        aqua.dock(address(router), hash, _t(a, b));
        vm.prank(alice);
        sm.markDocked(h);
        (,, st,,,) = sm.records(h);
        assertEq(uint8(st), 2);
    }

    function test_strategyManager_unshippedNotRegistrable() public {
        _subscribe(alice, 100_000e6);
        p = _strategy(SM.Kind.NAV_ANCHORED);
        vm.prank(alice);
        vm.expectRevert();
        sm.register(p);
    }

    function test_routerOnlyOwnerSetsTrust() public {
        vm.prank(bob);
        vm.expectRevert();
        router.setTrustedSource(address(0xBAD), true);
    }
}
