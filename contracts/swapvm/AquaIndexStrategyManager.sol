// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @notice Powered by SwapVM - © Degensoft Ltd 2025. AquaIndex protocol extension.

import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/contracts/libs/MakerTraits.sol";
import { Deadline, Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";
import { XYCSwap } from "@1inch/swap-vm/contracts/instructions/XYCSwap.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";

import { IndexNavGuard } from "./instructions/IndexNavGuard.sol";
import { IndexNavPriceAdjuster } from "./instructions/IndexNavPriceAdjuster.sol";
import { IndexInventorySkew } from "./instructions/IndexInventorySkew.sol";
import { IndexMaxTrade } from "./instructions/IndexMaxTrade.sol";
import { IndexCapabilityGuard } from "./instructions/IndexCapabilityGuard.sol";

/// @notice Non-custodial strategy tooling. Aqua `ship`/`dock` are keyed on msg.sender = maker, so the MAKER calls
///         Aqua directly; this contract (1) builds the canonical program/order/hash for a parameter set so the SDK,
///         UI and tests agree byte for byte, and (2) records/verifies the maker's shipped strategies against Aqua.
///         It never holds tokens or allowances.
contract AquaIndexStrategyManager {
    enum Kind {
        NAV_ANCHORED, // A: NAV price setter (+skew, limits)
        CONSERVATIVE, // B: same program, tighter parameters
        ADAPTIVE // C: XYCSwap curve, NAV price as a CAP, skew, limits
    }
    enum Status {
        NONE,
        ACTIVE,
        DOCKED
    }

    struct Params {
        Kind kind;
        address maker;
        address navSource;
        uint64 indexId;
        address indexToken;
        address quoteToken;
        uint40 expiry;
        uint64 salt;
        // NAV guard
        uint32 maxNavAge;
        uint64 minEpoch;
        uint16 maxNavDeviationBps;
        // NAV price
        int16 premiumBps;
        uint16 maxPremiumBps;
        uint16 maxDiscountBps;
        uint16 spreadBps;
        uint16 feeBps;
        // inventory skew
        uint16 targetShareBps;
        uint16 maxSkewBps;
        uint16 slopeBps;
        uint16 maxAdjustBps;
        // limits
        uint128 maxAmountIn;
        uint128 maxAmountOut;
        uint128 minLiquidityOut;
        // optional delegation (registry == 0 disables the guard)
        address capabilityRegistry;
        bytes32 capabilityId;
    }

    struct Record {
        address maker;
        Kind kind;
        Status status;
        uint32 version;
        address tokenA;
        address tokenB;
    }

    error NotShipped(bytes32 hash, address token);
    error NotDocked(bytes32 hash);
    error NotOwner();
    error Unknown(bytes32 hash);

    uint32 public constant INSTRUCTION_SET_VERSION = 1;

    IAqua public immutable aqua;
    address public immutable router;

    mapping(bytes32 => Record) public records;
    mapping(address => uint32) public versionOf; // per maker, increments with every registration

    event StrategyRegistered(address indexed maker, bytes32 indexed hash, Kind kind, uint32 version);
    event StrategyMarkedDocked(address indexed maker, bytes32 indexed hash);

    constructor(IAqua aqua_, address router_) {
        aqua = aqua_;
        router = router_;
    }

    function buildProgram(Params memory p) public pure returns (bytes memory prog) {
        prog = bytes.concat(Deadline.build(p.expiry), Salt.build(p.salt));
        prog = bytes.concat(
            prog, IndexNavGuard.build(p.navSource, p.indexId, p.maxNavAge, p.minEpoch, p.maxNavDeviationBps)
        );
        bool adaptive = p.kind == Kind.ADAPTIVE;
        if (adaptive) prog = bytes.concat(prog, XYCSwap.build());
        prog = bytes.concat(
            prog,
            IndexNavPriceAdjuster.build(
                IndexNavPriceAdjuster.Params({
                    navSource: p.navSource,
                    indexId: p.indexId,
                    quoteToken: p.quoteToken,
                    premiumBps: p.premiumBps,
                    maxPremiumBps: p.maxPremiumBps,
                    maxDiscountBps: p.maxDiscountBps,
                    spreadBps: p.spreadBps,
                    feeBps: p.feeBps,
                    mode: adaptive ? IndexNavPriceAdjuster.MODE_CAP : IndexNavPriceAdjuster.MODE_SET
                })
            ),
            IndexInventorySkew.build(
                IndexInventorySkew.Params({
                    navSource: p.navSource,
                    indexId: p.indexId,
                    quoteToken: p.quoteToken,
                    targetShareBps: p.targetShareBps,
                    maxSkewBps: p.maxSkewBps,
                    slopeBps: p.slopeBps,
                    maxAdjustBps: p.maxAdjustBps
                })
            ),
            IndexMaxTrade.build(p.navSource, p.indexId, p.maxAmountIn, p.maxAmountOut, p.minLiquidityOut)
        );
        if (p.capabilityRegistry != address(0)) {
            prog = bytes.concat(prog, IndexCapabilityGuard.build(p.capabilityRegistry, p.capabilityId));
        }
    }

    function buildOrder(Params memory p) public pure returns (ISwapVM.Order memory order, bytes32 hash) {
        (address a, address b) = p.indexToken < p.quoteToken ? (p.indexToken, p.quoteToken) : (p.quoteToken, p.indexToken);
        order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: p.maker,
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
                program: buildProgram(p)
            })
        );
        hash = keccak256(abi.encode(order));
    }

    /// @notice Maker registers a strategy it has ALREADY shipped to Aqua for THIS router (verified via Aqua balances).
    function register(Params calldata p) external returns (bytes32 hash) {
        require(p.maker == msg.sender, NotOwner());
        (ISwapVM.Order memory order, bytes32 h) = buildOrder(p);
        hash = h;
        (address a, address b) = (p.indexToken < p.quoteToken) ? (p.indexToken, p.quoteToken) : (p.quoteToken, p.indexToken);
        _requireActive(msg.sender, hash, a);
        _requireActive(msg.sender, hash, b);
        order; // silence: order is only built to derive the hash
        uint32 v = ++versionOf[msg.sender];
        records[hash] = Record(msg.sender, p.kind, Status.ACTIVE, v, a, b);
        emit StrategyRegistered(msg.sender, hash, p.kind, v);
    }

    /// @notice After the maker called `aqua.dock`, mark the record docked (reads Aqua's own state).
    function markDocked(bytes32 hash) external {
        Record storage r = records[hash];
        require(r.maker != address(0), Unknown(hash));
        require(r.maker == msg.sender, NotOwner());
        (, uint8 count) = aqua.rawBalances(r.maker, router, hash, r.tokenA);
        require(count == 0xff, NotDocked(hash));
        r.status = Status.DOCKED;
        emit StrategyMarkedDocked(msg.sender, hash);
    }

    /// @notice Aqua virtual balances for a strategy of this router.
    function balances(address maker, bytes32 hash, address tokenA, address tokenB)
        external
        view
        returns (uint256 balanceA, uint256 balanceB)
    {
        (uint248 a,) = aqua.rawBalances(maker, router, hash, tokenA);
        (uint248 b,) = aqua.rawBalances(maker, router, hash, tokenB);
        return (a, b);
    }

    function _requireActive(address maker, bytes32 hash, address token) private view {
        (, uint8 count) = aqua.rawBalances(maker, router, hash, token);
        require(count != 0 && count != 0xff, NotShipped(hash, token));
    }
}
