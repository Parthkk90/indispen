// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @notice Powered by SwapVM - © Degensoft Ltd 2025. AquaIndex protocol extension.

import { Opcode } from "@1inch/swap-vm/contracts/libs/OpcodeList.sol";
import { IAquaIndexRouterConfig } from "./AquaIndexInterfaces.sol";

/// @notice Shared helpers: wire header `[opcode:1][argsLength:1]`, strict length checks, trusted-source check.
library AquaIndexArgs {
    error AquaIndexBadArgsLength(uint256 expected, uint256 actual);
    error AquaIndexUntrustedSource(address source);

    uint256 internal constant BPS = 10_000;

    function header(Opcode opcode, uint256 length) internal pure returns (bytes memory) {
        require(length < 256, AquaIndexBadArgsLength(255, length));
        // forge-lint: disable-next-line(unsafe-typecast)
        return abi.encodePacked(opcode.asU8(), uint8(length));
    }

    function requireLength(bytes calldata args, uint256 expected) internal pure {
        require(args.length == expected, AquaIndexBadArgsLength(expected, args.length));
    }

    /// @dev Instructions run inside the router's context, so `address(this)` is the router and its allowlist applies.
    function requireTrusted(address source) internal view {
        require(IAquaIndexRouterConfig(address(this)).isTrustedSource(source), AquaIndexUntrustedSource(source));
    }
}
