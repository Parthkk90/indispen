// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AquaRouter } from "@1inch/aqua/src/AquaRouter.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/contracts/libs/TakerTraits.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/contracts/libs/MakerTraits.sol";
import { Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";
import { XYCSwap } from "@1inch/swap-vm/contracts/instructions/XYCSwap.sol";

import { MockERC20 } from "../contracts/mocks/MockERC20.sol";
import { IndexRegistry } from "../contracts/index/IndexRegistry.sol";
import { IndexVault } from "../contracts/index/IndexVault.sol";
import { NAVOracle } from "../contracts/index/NAVOracle.sol";
import { SubscriptionManager } from "../contracts/index/SubscriptionManager.sol";
import { RedemptionManager } from "../contracts/index/RedemptionManager.sol";
import { RebalanceManager } from "../contracts/index/RebalanceManager.sol";
import { AquaIndexSwapVMRouter } from "../contracts/swapvm/AquaIndexSwapVMRouter.sol";
import { AquaIndexStrategyManager as SM } from "../contracts/swapvm/AquaIndexStrategyManager.sol";

/// @notice End-to-end AquaIndex demo against the deployment in deployments/<chainid>.json (Sepolia, SYNTHETIC tokens).
///         Needs PRIVATE_KEY (maker/admin) and TAKER_KEY (trader). Every step logs live on-chain values.
contract Demo is Script {
    using stdJson for string;

    struct Ctx {
        AquaRouter aqua;
        AquaIndexSwapVMRouter router;
        IndexRegistry registry;
        NAVOracle oracle;
        SubscriptionManager subs;
        RedemptionManager reds;
        RebalanceManager rebal;
        SM sm;
        MockERC20 usdc;
        IERC20 share;
        IndexVault vault;
        MockERC20[5] assets;
        uint64 idx;
        address maker;
        address taker;
    }

    Ctx internal c;
    uint256 internal pk;
    uint256 internal tk;

    function _load() internal {
        string memory j = vm.readFile(string.concat("./deployments/", vm.toString(block.chainid), ".json"));
        c.aqua = AquaRouter(j.readAddress(".aqua"));
        c.router = AquaIndexSwapVMRouter(payable(j.readAddress(".router")));
        c.registry = IndexRegistry(j.readAddress(".registry"));
        c.oracle = NAVOracle(j.readAddress(".oracle"));
        c.subs = SubscriptionManager(j.readAddress(".subscriptionManager"));
        c.reds = RedemptionManager(j.readAddress(".redemptionManager"));
        c.rebal = RebalanceManager(j.readAddress(".rebalanceManager"));
        c.sm = SM(j.readAddress(".strategyManager"));
        c.usdc = MockERC20(j.readAddress(".usdc"));
        c.share = IERC20(j.readAddress(".share"));
        c.vault = IndexVault(j.readAddress(".vault"));
        c.idx = uint64(j.readUint(".indexId"));
        c.assets[0] = MockERC20(j.readAddress(".mBTC"));
        c.assets[1] = MockERC20(j.readAddress(".mETH"));
        c.assets[2] = MockERC20(j.readAddress(".mSOL"));
        c.assets[3] = MockERC20(j.readAddress(".mLINK"));
        c.assets[4] = MockERC20(j.readAddress(".mUNI"));
        c.maker = vm.addr(pk);
        c.taker = vm.addr(tk);
    }

    function _params(uint64 salt, uint16 slope) internal view returns (SM.Params memory p) {
        p.kind = SM.Kind.NAV_ANCHORED;
        p.maker = c.maker;
        p.navSource = address(c.oracle);
        p.indexId = c.idx;
        p.indexToken = address(c.share);
        p.quoteToken = address(c.usdc);
        p.expiry = uint40(block.timestamp + 7 days);
        p.salt = salt;
        p.maxNavAge = 30 minutes;
        p.minEpoch = 1;
        p.maxNavDeviationBps = 100;
        p.maxPremiumBps = 300;
        p.maxDiscountBps = 300;
        p.spreadBps = 20;
        p.targetShareBps = 5000;
        p.maxSkewBps = 4000;
        p.slopeBps = slope;
        p.maxAdjustBps = 500;
        p.maxAmountIn = 20_000e6;
    }

    function _td(address taker, address tIn, address tOut) internal pure returns (bytes memory) {
        TakerTraitsLib.Args memory a;
        a.taker = taker;
        a.isExactIn = true;
        a.isAToB = tIn < tOut;
        a.threshold = abi.encode(uint256(0));
        a.useTransferFromAndAquaPush = true;
        return TakerTraitsLib.build(a);
    }

    function _sorted(address x, address y) internal pure returns (address, address) {
        return x < y ? (x, y) : (y, x);
    }

    function _ship(ISwapVM.Order memory o, address x, address y, uint256 ax, uint256 ay) internal {
        (address a, address b) = _sorted(x, y);
        address[] memory t = new address[](2);
        uint256[] memory amt = new uint256[](2);
        t[0] = a;
        t[1] = b;
        amt[0] = a == x ? ax : ay;
        amt[1] = a == x ? ay : ax;
        c.aqua.ship(address(c.router), abi.encode(o), t, amt);
    }

    function _quoteBuy(ISwapVM.Order memory o, uint256 usdcIn) internal returns (uint256 out) {
        uint256 snap = vm.snapshotState();
        vm.prank(c.taker);
        (, out,) = c.router.quote(o, usdcIn, _td(c.taker, address(c.usdc), address(c.share)));
        vm.revertToState(snap); // quotes must leave no trace (incl. the pranked account's nonce)
    }

    function _xycOrder(address asset, uint64 salt) internal view returns (ISwapVM.Order memory) {
        (address a, address b) = _sorted(asset, address(c.usdc));
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: c.maker,
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

    function run() external {
        pk = vm.envUint("PRIVATE_KEY");
        tk = vm.envUint("TAKER_KEY");
        _load();
        uint64 salt = uint64(block.timestamp);
        console.log("== AquaIndex Sepolia demo (SYNTHETIC tokens, self-deployed upstream Aqua) ==");

        bool skipSetup = vm.envOr("SKIP_SETUP", false);
        if (!skipSetup) _setup(salt);
        _trade(salt);
    }

    function _setup(uint64 salt) internal {
        // 1-4 subscribe, publish NAV
        vm.startBroadcast(pk);
        c.usdc.mint(c.maker, 300_000e6);
        c.usdc.approve(address(c.subs), type(uint256).max);
        uint256 shares = c.subs.subscribe(c.idx, 100_000e6, 0);
        console.log("subscribed 100,000 mUSDC -> shares", shares);
        c.oracle.publishNav(c.idx);
        (uint256 nav,, uint256 nps) = c.oracle.computeNav(c.idx);
        console.log("NAV (1e18 USD)", nav);
        console.log("NAV/share (1e18)", nps);
        console.log("vault backing verified", c.vault.verifyBacking());
        vm.stopBroadcast();

        // 5 rebalance idle cash through Aqua XYC dealer strategies (maker doubles as dealer)
        vm.startBroadcast(pk);
        uint256[5] memory px = [uint256(90000), 3000, 150, 15, 8];
        c.usdc.approve(address(c.aqua), type(uint256).max);
        for (uint256 i; i < 5; ++i) {
            MockERC20 a = c.assets[i];
            a.mint(c.maker, 10_000e18);
            a.approve(address(c.aqua), type(uint256).max);
            c.usdc.mint(c.maker, 10_000e18 * px[i] / 1e12);
            ISwapVM.Order memory xo = _xycOrder(address(a), salt + uint64(i));
            _ship(xo, address(a), address(c.usdc), 10_000e18, 10_000e18 * px[i] / 1e12);
            bytes memory td = _td(address(c.rebal), address(c.usdc), address(a));
            (uint256 sold, uint256 bought) = c.rebal.execute(c.idx, address(c.usdc), address(a), 20_000e6, xo, td, 0);
            console.log("rebalanced: sold mUSDC", sold);
            console.log("            bought asset", bought);
        }
        {
            (uint256 navAfter,,) = c.oracle.computeNav(c.idx);
            console.log("NAV after rebalance", navAfter);
        }
        c.oracle.publishNav(c.idx);
        vm.stopBroadcast();
    }

    function _trade(uint64 salt) internal {
        // 6 ship Strategy A (NAV anchored + skew + max trade), register
        SM.Params memory p = _params(salt, 5000);
        (ISwapVM.Order memory order, bytes32 hash) = c.sm.buildOrder(p);
        vm.startBroadcast(pk);
        c.share.approve(address(c.aqua), type(uint256).max);
        _ship(order, address(c.share), address(c.usdc), 500e18, 50_000e6);
        c.sm.register(p);
        vm.stopBroadcast();
        console.log("Strategy A hash");
        console.logBytes32(hash);

        // 7 quote via the CUSTOM router, then execute
        uint256 q1 = _quoteBuy(order, 1_000e6);
        console.log("quote: 1000 mUSDC -> shares", q1);
        if (vm.envOr("TAKER_NONCE", uint256(0)) != 0) vm.setNonce(c.taker, uint64(vm.envUint("TAKER_NONCE")));
        vm.startBroadcast(tk);
        c.usdc.mint(c.taker, 10_000e6);
        c.usdc.approve(address(c.router), type(uint256).max);
        (, uint256 got,) = c.router.swap(order, 1_000e6, _td(c.taker, address(c.usdc), address(c.share)));
        vm.stopBroadcast();
        console.log("swap executed, shares received", got);
        console.log("quote == swap", q1 == got);

        // 8 NAV change: mBTC +20% -> republish -> changed quote
        vm.startBroadcast(pk);
        c.oracle.setPrice(address(c.assets[0]), 108000e18);
        c.oracle.publishNav(c.idx);
        vm.stopBroadcast();
        uint256 q2 = _quoteBuy(order, 1_000e6);
        console.log("quote after NAV change", q2);

        // 9 inventory change: second strategy with a share-heavy inventory (same NAV) -> different price
        SM.Params memory p2 = _params(salt + 100, 5000);
        (ISwapVM.Order memory order2,) = c.sm.buildOrder(p2);
        vm.startBroadcast(pk);
        _ship(order2, address(c.share), address(c.usdc), 400e18, 20_000e6);
        vm.stopBroadcast();
        uint256 q3 = _quoteBuy(order2, 1_000e6);
        console.log("quote, share-heavy inventory", q3);

        // 10 risk limit blocks an oversized trade (maxAmountIn 20k)
        uint256 snap2 = vm.snapshotState();
        vm.prank(c.taker);
        try c.router.quote(order, 25_000e6, _td(c.taker, address(c.usdc), address(c.share))) {
            console.log("ERROR: oversize trade was not blocked");
        } catch {
            console.log("oversized trade (25,000 > 20,000 limit) correctly reverted");
        }
        vm.revertToState(snap2);

        // 11 redeem in kind, final accounting
        vm.startBroadcast(pk);
        c.share.approve(address(c.reds), type(uint256).max);
        c.reds.redeemInKind(c.idx, 100e18);
        vm.stopBroadcast();
        (uint256 navF, uint256 supplyF, uint256 npsF) = c.oracle.computeNav(c.idx);
        console.log("FINAL NAV", navF);
        console.log("FINAL supply", supplyF);
        console.log("FINAL NAV/share", npsF);
        console.log("FINAL backing verified", c.vault.verifyBacking());
    }
}
