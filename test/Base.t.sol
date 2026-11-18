// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { AquaRouter } from "@1inch/aqua/src/AquaRouter.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/contracts/libs/TakerTraits.sol";

import { MockERC20 } from "../contracts/mocks/MockERC20.sol";
import { IndexRegistry } from "../contracts/index/IndexRegistry.sol";
import { IndexVault } from "../contracts/index/IndexVault.sol";
import { IndexShare } from "../contracts/index/IndexShare.sol";
import { NAVOracle } from "../contracts/index/NAVOracle.sol";
import { SubscriptionManager } from "../contracts/index/SubscriptionManager.sol";
import { RedemptionManager } from "../contracts/index/RedemptionManager.sol";
import { RebalanceManager } from "../contracts/index/RebalanceManager.sol";
import { AquaIndexSwapVMRouter } from "../contracts/swapvm/AquaIndexSwapVMRouter.sol";
import { AquaIndexStrategyManager } from "../contracts/swapvm/AquaIndexStrategyManager.sol";
import { AquaIndexCapabilityRegistry } from "../contracts/swapvm/AquaIndexCapabilityRegistry.sol";

/// @dev Full local stack on the REAL upstream Aqua (AquaRouter) and the custom router.
abstract contract Base is Test {
    address internal admin = address(this);
    address internal alice = vm.addr(101); // subscriber + market maker
    address internal bob = vm.addr(102); // taker
    address internal carol = vm.addr(103); // operator / second taker

    MockERC20 internal usdc;
    MockERC20[5] internal assets;

    AquaRouter internal aqua;
    AquaIndexSwapVMRouter internal router;
    IndexRegistry internal registry;
    NAVOracle internal oracle;
    SubscriptionManager internal subs;
    RedemptionManager internal reds;
    RebalanceManager internal rebal;
    AquaIndexStrategyManager internal sm;
    AquaIndexCapabilityRegistry internal caps;

    uint64 internal idx;
    IndexVault internal vault;
    IndexShare internal share;

    function setUp() public virtual {
        vm.warp(1_800_000_000);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        string[5] memory sy = ["mRELI", "mTCS", "mHDFC", "mINFY", "mICICI"];
        for (uint256 i; i < 5; ++i) {
            assets[i] = new MockERC20(sy[i], sy[i], 18);
        }

        aqua = new AquaRouter(address(this));
        router = new AquaIndexSwapVMRouter(address(aqua), address(0xdead), address(this), "AquaIndexSwapVMRouter", "1");
        registry = new IndexRegistry(admin, address(usdc));
        oracle = new NAVOracle(admin, registry);
        subs = new SubscriptionManager(registry, oracle);
        reds = new RedemptionManager(registry, oracle);
        rebal = new RebalanceManager(admin, registry, oracle, address(router));
        registry.setManagers(address(subs), address(reds), address(rebal));
        sm = new AquaIndexStrategyManager(IAqua(address(aqua)), address(router));
        caps = new AquaIndexCapabilityRegistry();
        router.setTrustedSource(address(oracle), true);
        router.setTrustedSource(address(caps), true);

        oracle.setPrice(address(usdc), 1e18);
        uint256[5] memory px = [uint256(2500e18), 4000e18, 1600e18, 1500e18, 1100e18];
        address[] memory c = new address[](5);
        uint16[] memory w = new uint16[](5);
        for (uint256 i; i < 5; ++i) {
            oracle.setPrice(address(assets[i]), px[i]);
            c[i] = address(assets[i]);
            w[i] = 2000;
        }
        idx = registry.createIndex("India 50 Demo Index", "I50D", "ipfs://demo", c, w, 100e18, 0, 0);
        IndexRegistry.Index memory ix = registry.getIndex(idx);
        vault = IndexVault(ix.vault);
        share = IndexShare(ix.share);

        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        usdc.mint(carol, 1_000_000e6);
        vm.startPrank(alice);
        usdc.approve(address(subs), type(uint256).max);
        usdc.approve(address(aqua), type(uint256).max);
        share.approve(address(aqua), type(uint256).max);
        share.approve(address(reds), type(uint256).max);
        vm.stopPrank();
        for (uint256 i; i < 2; ++i) {
            address t = i == 0 ? bob : carol;
            vm.startPrank(t);
            usdc.approve(address(router), type(uint256).max);
            share.approve(address(router), type(uint256).max);
            usdc.approve(address(subs), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _subscribe(address who, uint256 amount) internal returns (uint256) {
        vm.prank(who);
        return subs.subscribe(idx, amount, 0);
    }

    function _publish() internal {
        oracle.publishNav(idx);
    }

    function _takerData(address taker, address tokenIn, address tokenOut, bool exactIn) internal pure returns (bytes memory) {
        TakerTraitsLib.Args memory a;
        a.taker = taker;
        a.isExactIn = exactIn;
        a.isAToB = tokenIn < tokenOut;
        a.threshold = exactIn ? abi.encode(uint256(0)) : abi.encode(type(uint256).max);
        a.useTransferFromAndAquaPush = true;
        return TakerTraitsLib.build(a);
    }

    function _ship(ISwapVM.Order memory order, address tokenA, address tokenB, uint256 amtA, uint256 amtB)
        internal
        returns (bytes32)
    {
        address[] memory t = new address[](2);
        uint256[] memory a = new uint256[](2);
        t[0] = tokenA;
        t[1] = tokenB;
        a[0] = amtA;
        a[1] = amtB;
        vm.prank(order.maker);
        return aqua.ship(address(router), abi.encode(order), t, a);
    }

    function _quote(ISwapVM.Order memory order, address taker, address tIn, address tOut, uint256 amount, bool exactIn)
        internal
        returns (uint256 amtIn, uint256 amtOut)
    {
        bytes memory td = _takerData(taker, tIn, tOut, exactIn);
        vm.prank(taker);
        (amtIn, amtOut,) = router.quote(order, amount, td);
    }

    function _swap(ISwapVM.Order memory order, address taker, address tIn, address tOut, uint256 amount, bool exactIn)
        internal
        returns (uint256 amtIn, uint256 amtOut)
    {
        bytes memory td = _takerData(taker, tIn, tOut, exactIn);
        vm.prank(taker);
        (amtIn, amtOut,) = router.swap(order, amount, td);
    }

    function _strategy(AquaIndexStrategyManager.Kind kind) internal view returns (AquaIndexStrategyManager.Params memory p) {
        p.kind = kind;
        p.maker = alice;
        p.navSource = address(oracle);
        p.indexId = idx;
        p.indexToken = address(share);
        p.quoteToken = address(usdc);
        p.expiry = uint40(block.timestamp + 30 days);
        p.salt = 1;
        p.maxNavAge = 5 minutes;
        p.minEpoch = 1;
        p.maxNavDeviationBps = 100;
        p.premiumBps = 0;
        p.maxPremiumBps = 300;
        p.maxDiscountBps = 300;
        p.spreadBps = 20;
        p.feeBps = 0;
        p.targetShareBps = 5000;
        p.maxSkewBps = 3000;
        p.slopeBps = 0; // skew disabled by default; skew tests enable it
        p.maxAdjustBps = 0;
        p.maxAmountIn = 0;
        p.maxAmountOut = 0;
        p.minLiquidityOut = 0;
    }

    /// @dev alice subscribes 100k USDC (1000 shares @ $100), publishes NAV, ships 500 shares + 50k USDC.
    function _bootstrapMarket(AquaIndexStrategyManager.Params memory p)
        internal
        returns (ISwapVM.Order memory order, bytes32 hash)
    {
        if (share.totalSupply() == 0) {
            _subscribe(alice, 100_000e6);
            _publish();
        }
        (order, hash) = sm.buildOrder(p);
        (address a, address b) = address(share) < address(usdc) ? (address(share), address(usdc)) : (address(usdc), address(share));
        uint256 sAmt = 500e18;
        uint256 qAmt = 50_000e6;
        _ship(order, a, b, a == address(share) ? sAmt : qAmt, a == address(share) ? qAmt : sAmt);
    }
}
