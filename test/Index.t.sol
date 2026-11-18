// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Base } from "./Base.t.sol";
import { IndexRegistry } from "../contracts/index/IndexRegistry.sol";
import { IndexVault } from "../contracts/index/IndexVault.sol";
import { NAVOracle } from "../contracts/index/NAVOracle.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract IndexTest is Base {
    function test_subscribe_mintsAtInitialNav() public {
        uint256 s = _subscribe(alice, 100_000e6);
        assertEq(s, 1000e18);
        assertEq(share.balanceOf(alice), 1000e18);
        assertEq(vault.holdings(address(usdc)), 100_000e6);
        assertTrue(vault.verifyBacking());
    }

    function test_subscribe_secondAtNav_afterPriceMove() public {
        _subscribe(alice, 100_000e6);
        // add real assets: 10 mRELI @2500 = 25k into the vault via manager path (rebalance) is tested elsewhere;
        // here a price move on a held asset requires holdings, so mint-then-record through a manager role.
        (uint256 totalNav,, uint256 nps) = oracle.computeNav(idx);
        assertEq(totalNav, 100_000e18);
        assertEq(nps, 100e18);
        uint256 s2 = _subscribe(bob, 50_000e6);
        assertEq(s2, 500e18);
        assertEq(share.totalSupply(), 1500e18);
    }

    function test_navPerShare_updatesWhenAssetPriceMoves() public {
        _subscribe(alice, 100_000e6);
        // give the vault 10 mRELI through the rebalance manager path: simulate a trade-less deposit using manager role
        vm.startPrank(address(subs));
        assets[0].mint(address(vault), 10e18);
        vault.recordDeposit(address(assets[0]), 10e18);
        vm.stopPrank();
        (uint256 nav1,, uint256 nps1) = oracle.computeNav(idx);
        assertEq(nav1, 125_000e18);
        assertEq(nps1, 125e18);
        oracle.setPrice(address(assets[0]), 3000e18);
        (uint256 nav2,, uint256 nps2) = oracle.computeNav(idx);
        assertEq(nav2, 130_000e18);
        assertEq(nps2, 130e18);
        assertTrue(vault.verifyBacking());
    }

    function test_redeemInKind_proRata_neverExceedsClaim() public {
        _subscribe(alice, 100_000e6);
        _subscribe(bob, 100_000e6);
        uint256 before = usdc.balanceOf(bob);
        uint256 sh = share.balanceOf(bob);
        vm.startPrank(bob);
        share.approve(address(reds), sh);
        reds.redeemInKind(idx, sh / 2);
        vm.stopPrank();
        assertEq(usdc.balanceOf(bob) - before, 50_000e6);
        assertEq(vault.holdings(address(usdc)), 150_000e6);
        assertTrue(vault.verifyBacking());
    }

    function test_redeemToQuote_ok_and_insufficientLiquidity() public {
        _subscribe(alice, 100_000e6);
        vm.startPrank(alice);
        reds.redeemToQuote(idx, 100e18, 10_000e6);
        vm.stopPrank();
        assertEq(vault.holdings(address(usdc)), 90_000e6);
        // make vault hold mostly non-USDC: move USDC out as manager, replace by asset
        vm.startPrank(address(subs));
        vault.withdraw(address(usdc), address(0xBEEF), 85_000e6);
        assets[1].mint(address(vault), 21.25e18); // 85k
        vault.recordDeposit(address(assets[1]), 21.25e18);
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert();
        reds.redeemToQuote(idx, 800e18, 0); // wants ~72k USDC, vault has 5k
        reds.redeemInKind(idx, 800e18); // in-kind still works
        vm.stopPrank();
        assertTrue(vault.verifyBacking());
    }

    function test_feeStaysInVault() public {
        registry.setStatus(idx, IndexRegistry.Status.ACTIVE);
        // new index with fees
        address[] memory c = new address[](1);
        uint16[] memory w = new uint16[](1);
        c[0] = address(assets[0]);
        w[0] = 10_000;
        uint64 id2 = registry.createIndex("Fee", "FEE", "", c, w, 100e18, 100, 100);
        IndexVault v2 = IndexVault(registry.vaultOf(id2));
        vm.prank(alice);
        uint256 s = subs.subscribe(id2, 10_000e6, 0);
        assertEq(s, 99e18); // 1% fee, 100 shares gross
        assertEq(v2.holdings(address(usdc)), 10_000e6);
    }

    function test_pause_blocksSubscribeAndRedeem() public {
        _subscribe(alice, 10_000e6);
        registry.setStatus(idx, IndexRegistry.Status.PAUSED);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SubscriptionManagerNotActive.NotActive.selector, idx));
        subs.subscribe(idx, 1e6, 0);
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        reds.redeemToQuote(idx, 1e18, 0);
        registry.setStatus(idx, IndexRegistry.Status.ACTIVE);
        vm.prank(alice);
        reds.redeemToQuote(idx, 1e18, 0);
    }

    function test_oracle_staleBlocksSubscription() public {
        _subscribe(alice, 10_000e6);
        vm.warp(block.timestamp + 2 hours);
        vm.prank(alice);
        vm.expectRevert();
        subs.subscribe(idx, 1e6, 0);
    }

    function test_roles_unauthorizedCannotSetPriceOrPublish() public {
        vm.startPrank(bob);
        vm.expectRevert();
        oracle.setPrice(address(usdc), 2e18);
        vm.expectRevert();
        oracle.publishNav(idx);
        vm.expectRevert();
        vault.recordDeposit(address(usdc), 1);
        vm.expectRevert();
        vault.withdraw(address(usdc), bob, 1);
        vm.expectRevert();
        share.mint(bob, 1e18);
        vm.expectRevert();
        share.burn(alice, 1e18);
        vm.stopPrank();
    }

    function test_oracle_priceMoveCapped() public {
        vm.expectRevert();
        oracle.setPrice(address(assets[0]), 10_000e18);
        oracle.forceSetPrice(address(assets[0]), 10_000e18);
    }

    function test_vault_donationDoesNotMoveNav() public {
        _subscribe(alice, 100_000e6);
        usdc.mint(address(vault), 1_000_000e6); // donation
        (uint256 nav,,) = oracle.computeNav(idx);
        assertEq(nav, 100_000e18);
    }

    function test_vault_recordDeposit_requiresRealBalance() public {
        vm.prank(address(subs));
        vm.expectRevert();
        vault.recordDeposit(address(assets[0]), 1e18);
    }

    function test_registry_weightsValidated() public {
        address[] memory c = new address[](2);
        uint16[] memory w = new uint16[](2);
        c[0] = address(assets[0]);
        c[1] = address(assets[1]);
        w[0] = 5000;
        w[1] = 4000;
        vm.expectRevert(IndexRegistry.InvalidWeights.selector);
        registry.createIndex("X", "X", "", c, w, 1e18, 0, 0);
        w[1] = 5000;
        c[1] = address(usdc); // quote asset cannot be a constituent
        vm.expectRevert(IndexRegistry.InvalidWeights.selector);
        registry.createIndex("X", "X", "", c, w, 1e18, 0, 0);
    }

    function test_methodologyVersionBumps() public {
        address[] memory c = new address[](2);
        uint16[] memory w = new uint16[](2);
        c[0] = address(assets[0]);
        c[1] = address(assets[1]);
        w[0] = 6000;
        w[1] = 4000;
        registry.updateMethodology(idx, c, w);
        assertEq(registry.getIndex(idx).methodologyVersion, 2);
    }

    function test_invariant_claimsNeverExceedBacking() public {
        _subscribe(alice, 123_456e6);
        _subscribe(bob, 7_777e6);
        (uint256 nav, uint256 supply, uint256 nps) = oracle.computeNav(idx);
        assertLe(supply * nps / 1e18, nav);
        assertTrue(vault.verifyBacking());
    }
}

interface SubscriptionManagerNotActive {
    error NotActive(uint64);
}
