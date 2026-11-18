// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @notice Powered by SwapVM - © Degensoft Ltd 2025. AquaIndex protocol extension.

struct NavSnapshot {
    uint256 navPerShare; // 1e18 USD per whole share
    uint256 totalNav; // 1e18 USD, verified on-chain from vault balances x prices at publish time
    uint256 supplyRef; // share supply (raw) used at publish time
    uint40 updatedAt;
    uint64 epoch; // increments on every publish
}

/// @notice Read surface the custom instructions use on the NAV oracle.
interface IAquaIndexNavSource {
    function navSnapshot(uint64 indexId) external view returns (NavSnapshot memory);
    function isTradable(uint64 indexId) external view returns (bool);
    function shareToken(uint64 indexId) external view returns (address);
    /// @dev 1e18 USD per whole token; reverts when the price is stale or unset.
    function assetPrice(address asset) external view returns (uint256);
}

struct Capability {
    address maker; // grantor: the Aqua maker whose strategy is being operated
    address operator; // the only taker allowed
    uint64 indexId;
    address tokenA;
    address tokenB;
    uint128 maxAmountIn;
    uint40 expiry;
    uint64 nonce;
    bool revoked;
}

interface IAquaIndexCapabilities {
    function getCapability(bytes32 id) external view returns (Capability memory);
    function minNonce(address maker) external view returns (uint64);
}

/// @notice Implemented by the router: the allowlist of external sources instructions may read.
interface IAquaIndexRouterConfig {
    function isTrustedSource(address source) external view returns (bool);
}
