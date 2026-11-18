// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { AquaRouter } from "@1inch/aqua/src/AquaRouter.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";

import { MockERC20 } from "../contracts/mocks/MockERC20.sol";
import { IndexRegistry } from "../contracts/index/IndexRegistry.sol";
import { NAVOracle } from "../contracts/index/NAVOracle.sol";
import { SubscriptionManager } from "../contracts/index/SubscriptionManager.sol";
import { RedemptionManager } from "../contracts/index/RedemptionManager.sol";
import { RebalanceManager } from "../contracts/index/RebalanceManager.sol";
import { AquaIndexSwapVMRouter } from "../contracts/swapvm/AquaIndexSwapVMRouter.sol";
import { AquaIndexStrategyManager } from "../contracts/swapvm/AquaIndexStrategyManager.sol";
import { AquaIndexCapabilityRegistry } from "../contracts/swapvm/AquaIndexCapabilityRegistry.sol";

/// @notice Sepolia/local deployment. Sepolia has NO official 1inch Aqua deployment, so this script deploys the
///         upstream `AquaRouter` source itself (labelled `aquaDeployment: "self-deployed upstream source"`).
///         Everything minted here is a SYNTHETIC mock token with no value.
contract Deploy is Script {
    using stdJson for string;

    address constant SEPOLIA_WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        MockERC20 usdc = new MockERC20("Mock USDC (synthetic)", "mUSDC", 6);
        string[5] memory sy = ["mRELI", "mTCS", "mHDFC", "mINFY", "mICICI"];
        uint256[5] memory px = [uint256(2500e18), 4000e18, 1600e18, 1500e18, 1100e18];
        MockERC20[5] memory a;
        address[] memory c = new address[](5);
        uint16[] memory w = new uint16[](5);
        for (uint256 i; i < 5; ++i) {
            a[i] = new MockERC20(string.concat(sy[i], " receipt (synthetic)"), sy[i], 18);
            c[i] = address(a[i]);
            w[i] = 2000;
        }

        AquaRouter aqua = new AquaRouter(deployer);
        AquaIndexSwapVMRouter router =
            new AquaIndexSwapVMRouter(address(aqua), SEPOLIA_WETH, deployer, "AquaIndexSwapVMRouter", "1");

        IndexRegistry registry = new IndexRegistry(deployer, address(usdc));
        NAVOracle oracle = new NAVOracle(deployer, registry);
        SubscriptionManager subs = new SubscriptionManager(registry, oracle);
        RedemptionManager reds = new RedemptionManager(registry, oracle);
        RebalanceManager rebal = new RebalanceManager(deployer, registry, oracle, address(router));
        registry.setManagers(address(subs), address(reds), address(rebal));
        AquaIndexStrategyManager sm = new AquaIndexStrategyManager(IAqua(address(aqua)), address(router));
        AquaIndexCapabilityRegistry caps = new AquaIndexCapabilityRegistry();
        router.setTrustedSource(address(oracle), true);
        router.setTrustedSource(address(caps), true);

        oracle.setPrice(address(usdc), 1e18);
        for (uint256 i; i < 5; ++i) {
            oracle.setPrice(address(a[i]), px[i]);
        }
        // demo oracle window: 24h so the testnet demo does not go stale between scripts
        oracle.setParams(24 hours, 5000);
        uint64 id = registry.createIndex(
            "India 50 Demo Index", "I50D", "ipfs://aquaindex-demo (SYNTHETIC, not a licensed Nifty 50 product)", c, w, 100e18, 0, 0
        );
        usdc.mint(deployer, 1_000_000e6);
        vm.stopBroadcast();

        IndexRegistry.Index memory ix = registry.getIndex(id);
        string memory j = "d";
        j.serialize("network", string("sepolia"));
        j.serialize("chainId", block.chainid);
        j.serialize("deployer", deployer);
        j.serialize("instructionSetVersion", uint256(1));
        j.serialize("aquaDeployment", string("self-deployed upstream AquaRouter source (no official Aqua on Sepolia)"));
        j.serialize("aqua", address(aqua));
        j.serialize("router", address(router));
        j.serialize("registry", address(registry));
        j.serialize("oracle", address(oracle));
        j.serialize("subscriptionManager", address(subs));
        j.serialize("redemptionManager", address(reds));
        j.serialize("rebalanceManager", address(rebal));
        j.serialize("strategyManager", address(sm));
        j.serialize("capabilityRegistry", address(caps));
        j.serialize("usdc", address(usdc));
        j.serialize("indexId", uint256(id));
        j.serialize("vault", ix.vault);
        j.serialize("share", ix.share);
        for (uint256 i; i < 5; ++i) {
            j.serialize(sy[i], address(a[i]));
        }
        string memory out = j.serialize("weth", SEPOLIA_WETH);
        vm.writeJson(out, string.concat("./deployments/", vm.toString(block.chainid), ".json"));
        console.log("router", address(router));
    }
}
