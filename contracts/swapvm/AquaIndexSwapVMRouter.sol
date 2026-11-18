// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @notice Powered by SwapVM - © Degensoft Ltd 2025. AquaIndex protocol extension router.

import { Simulator } from "@1inch/solidity-utils/contracts/mixins/Simulator.sol";
import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";
import { SwapVM } from "@1inch/swap-vm/contracts/SwapVM.sol";

import { AquaIndexOpcodes } from "./opcodes/AquaIndexOpcodes.sol";
import { IAquaIndexRouterConfig } from "./instructions/AquaIndexInterfaces.sol";

/// @title AquaIndexSwapVMRouter
/// @notice Aqua-mode SwapVM router with the AquaIndex instruction set. Strategies are shipped to Aqua with THIS
///         contract as `app`; Aqua keys balances by (maker, app, strategyHash, token), so no other app's balance is
///         readable here. External sources (NAV oracle, capability registry) must be allowlisted by the owner and are
///         additionally bound inside every strategy hash.
contract AquaIndexSwapVMRouter is Simulator, SwapVM, AquaIndexOpcodes, IAquaIndexRouterConfig {
    mapping(address => bool) private _trusted;

    event TrustedSourceSet(address indexed source, bool trusted);

    constructor(address aqua, address weth, address owner, string memory name, string memory version)
        SwapVM(aqua, weth, owner, name, version)
    { }

    function setTrustedSource(address source, bool trusted) external onlyOwner {
        _trusted[source] = trusted;
        emit TrustedSourceSet(source, trusted);
    }

    function isTrustedSource(address source) external view returns (bool) {
        return _trusted[source];
    }

    function _dispatch(Context memory ctx, uint256 opcode, bytes calldata args) internal override {
        _runOpcode(ctx, opcode, args);
    }
}
