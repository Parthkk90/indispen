// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Capability } from "./instructions/AquaIndexInterfaces.sol";

/// @notice Maker-issued, revocable, expiring trading capabilities consumed by INDEX_CAPABILITY_GUARD_XD.
///         Only the grantor (maker) can create/revoke; `bumpMinNonce` revokes all of a maker's capabilities at once.
///         Stateless limits only: no cumulative spend is tracked.
contract AquaIndexCapabilityRegistry {
    error NotGrantor();
    error InvalidCapability();
    error Unknown(bytes32 id);

    mapping(bytes32 => Capability) private _caps;
    mapping(address => uint64) public minNonce;
    mapping(address => uint256) public issued;

    event CapabilityIssued(bytes32 indexed id, address indexed maker, address indexed operator, uint64 indexId, uint40 expiry);
    event CapabilityRevoked(bytes32 indexed id);
    event MinNonceBumped(address indexed maker, uint64 minNonce);

    function issue(
        address operator,
        uint64 indexId,
        address tokenA,
        address tokenB,
        uint128 maxAmountIn,
        uint40 expiry
    ) external returns (bytes32 id) {
        if (operator == address(0) || tokenA == tokenB || expiry <= block.timestamp || maxAmountIn == 0) {
            revert InvalidCapability();
        }
        id = keccak256(abi.encode(msg.sender, operator, indexId, tokenA, tokenB, issued[msg.sender]++));
        _caps[id] =
            Capability(msg.sender, operator, indexId, tokenA, tokenB, maxAmountIn, expiry, minNonce[msg.sender], false);
        emit CapabilityIssued(id, msg.sender, operator, indexId, expiry);
    }

    function revoke(bytes32 id) external {
        Capability storage c = _caps[id];
        if (c.maker == address(0)) revert Unknown(id);
        if (c.maker != msg.sender) revert NotGrantor();
        c.revoked = true;
        emit CapabilityRevoked(id);
    }

    function bumpMinNonce() external {
        uint64 n = minNonce[msg.sender] + 1;
        minNonce[msg.sender] = n;
        emit MinNonceBumped(msg.sender, n);
    }

    function getCapability(bytes32 id) external view returns (Capability memory) {
        Capability memory c = _caps[id];
        if (c.maker == address(0)) revert Unknown(id);
        return c;
    }
}
