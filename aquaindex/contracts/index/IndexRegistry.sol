// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IndexShare } from "./IndexShare.sol";
import { IndexVault } from "./IndexVault.sol";

/// @notice Creates indices (vault + share token), stores metadata, constituents, weights, methodology version, status.
contract IndexRegistry is AccessControl {
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    enum Status {
        NONE,
        ACTIVE,
        PAUSED,
        RETIRED
    }

    struct Index {
        string name;
        string symbol;
        string metadataURI;
        address vault;
        address share;
        uint32 methodologyVersion;
        Status status;
        uint256 initialNavPerShare; // 1e18 USD
        uint16 subscriptionFeeBps;
        uint16 redemptionFeeBps;
    }

    error InvalidWeights();
    error UnknownIndex(uint64 indexId);
    error ManagersNotSet();

    address public immutable quoteAsset;
    address public subscriptionManager;
    address public redemptionManager;
    address public rebalanceManager;

    uint64 public indexCount;
    mapping(uint64 => Index) private _index;
    mapping(uint64 => address[]) private _constituents;
    mapping(uint64 => uint16[]) private _weights;

    event ManagersSet(address subscription, address redemption, address rebalance);
    event IndexCreated(uint64 indexed indexId, address vault, address share, string symbol);
    event MethodologyUpdated(uint64 indexed indexId, uint32 version);
    event StatusChanged(uint64 indexed indexId, Status status);

    constructor(address admin, address quoteAsset_) {
        quoteAsset = quoteAsset_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CREATOR_ROLE, admin);
    }

    function setManagers(address sub, address red, address reb) external onlyRole(DEFAULT_ADMIN_ROLE) {
        subscriptionManager = sub;
        redemptionManager = red;
        rebalanceManager = reb;
        emit ManagersSet(sub, red, reb);
    }

    function createIndex(
        string calldata name,
        string calldata symbol,
        string calldata metadataURI,
        address[] calldata constituents,
        uint16[] calldata weightsBps,
        uint256 initialNavPerShare,
        uint16 subFeeBps,
        uint16 redFeeBps
    ) external onlyRole(CREATOR_ROLE) returns (uint64 id) {
        if (subscriptionManager == address(0)) revert ManagersNotSet();
        _checkWeights(constituents, weightsBps);
        require(initialNavPerShare != 0 && subFeeBps < 1000 && redFeeBps < 1000, "params");

        id = ++indexCount;
        IndexShare share = new IndexShare(name, symbol, address(this));
        IndexVault vault = new IndexVault(address(this));

        share.grantRole(share.MINTER_ROLE(), subscriptionManager);
        share.grantRole(share.BURNER_ROLE(), redemptionManager);
        vault.grantRole(vault.MANAGER_ROLE(), subscriptionManager);
        vault.grantRole(vault.MANAGER_ROLE(), redemptionManager);
        vault.grantRole(vault.MANAGER_ROLE(), rebalanceManager);
        // hand pause control and admin to the registry admin; the registry keeps admin to manage allowlists
        vault.grantRole(vault.PAUSER_ROLE(), msg.sender);

        vault.allowAsset(quoteAsset);
        for (uint256 i; i < constituents.length; ++i) {
            vault.allowAsset(constituents[i]);
        }

        _index[id] = Index(
            name,
            symbol,
            metadataURI,
            address(vault),
            address(share),
            1,
            Status.ACTIVE,
            initialNavPerShare,
            subFeeBps,
            redFeeBps
        );
        _constituents[id] = constituents;
        _weights[id] = weightsBps;
        emit IndexCreated(id, address(vault), address(share), symbol);
    }

    function updateMethodology(uint64 id, address[] calldata constituents, uint16[] calldata weightsBps)
        external
        onlyRole(CREATOR_ROLE)
    {
        Index storage ix = _requireIndex(id);
        _checkWeights(constituents, weightsBps);
        IndexVault v = IndexVault(ix.vault);
        for (uint256 i; i < constituents.length; ++i) {
            v.allowAsset(constituents[i]);
        }
        _constituents[id] = constituents;
        _weights[id] = weightsBps;
        ix.methodologyVersion += 1;
        emit MethodologyUpdated(id, ix.methodologyVersion);
    }

    function setStatus(uint64 id, Status status) external onlyRole(CREATOR_ROLE) {
        Index storage ix = _requireIndex(id);
        require(status != Status.NONE, "status");
        ix.status = status;
        IndexVault v = IndexVault(ix.vault);
        if (status == Status.ACTIVE && v.paused()) v.unpause();
        if (status != Status.ACTIVE && !v.paused()) v.pause();
        emit StatusChanged(id, status);
    }

    function getIndex(uint64 id) external view returns (Index memory) {
        return _requireIndexView(id);
    }

    function constituentsOf(uint64 id) external view returns (address[] memory, uint16[] memory) {
        _requireIndexView(id);
        return (_constituents[id], _weights[id]);
    }

    function statusOf(uint64 id) external view returns (Status) {
        return _index[id].status;
    }

    function vaultOf(uint64 id) external view returns (address) {
        return _index[id].vault;
    }

    function shareOf(uint64 id) external view returns (address) {
        return _index[id].share;
    }

    function _checkWeights(address[] calldata c, uint16[] calldata w) private view {
        if (c.length == 0 || c.length != w.length) revert InvalidWeights();
        uint256 sum;
        for (uint256 i; i < w.length; ++i) {
            if (c[i] == quoteAsset || c[i] == address(0) || w[i] == 0) revert InvalidWeights();
            for (uint256 j; j < i; ++j) {
                if (c[j] == c[i]) revert InvalidWeights();
            }
            sum += w[i];
        }
        if (sum != 10_000) revert InvalidWeights();
    }

    function _requireIndex(uint64 id) private view returns (Index storage ix) {
        ix = _index[id];
        if (ix.vault == address(0)) revert UnknownIndex(id);
    }

    function _requireIndexView(uint64 id) private view returns (Index memory) {
        Index memory ix = _index[id];
        if (ix.vault == address(0)) revert UnknownIndex(id);
        return ix;
    }
}
