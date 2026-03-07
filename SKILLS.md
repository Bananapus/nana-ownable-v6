# Juicebox Ownable

## Purpose

Drop-in Juicebox-aware replacement for OpenZeppelin `Ownable`. A contract inheriting `JBOwnable` can be owned by a Juicebox project (via its ERC-721 NFT) or a plain address, with delegated access through `JBPermissions`. When owned by a project, ownership dynamically follows the NFT holder -- no on-chain update is needed when the NFT changes hands.

## Contracts

| Contract | Role |
|----------|------|
| `JBOwnable` | Concrete implementation. Provides the `onlyOwner` modifier and `_emitTransferEvent` (resolves project NFT holder at emission time). Inherit this in your contract. |
| `JBOwnableOverrides` | Abstract base with all ownership state and logic: owner resolution, transfers, renunciation, permission delegation, and internal helpers. Only inherit this directly if you need to customize `_emitTransferEvent`. |

## Inheritance Chain

```
JBOwnable
  └── JBOwnableOverrides (abstract)
        ├── Context (@openzeppelin/contracts)
        ├── JBPermissioned (@bananapus/core-v6)
        └── IJBOwnable (interface)
```

## Key Functions

### Public / External

| Function | Contract | What it does |
|----------|----------|--------------|
| `owner()` | `JBOwnableOverrides` | Returns the current owner address. If `projectId != 0`, returns `PROJECTS.ownerOf(projectId)`. Otherwise returns `jbOwner.owner`. |
| `transferOwnership(address newOwner)` | `JBOwnableOverrides` | Transfers ownership to a new address. Reverts if `newOwner` is `address(0)`. Resets `permissionId` to 0. |
| `transferOwnershipToProject(uint256 projectId)` | `JBOwnableOverrides` | Transfers ownership to a Juicebox project. The NFT holder becomes the owner. Validates: `projectId != 0`, fits in `uint88`, and `projectId <= PROJECTS.count()`. Resets `permissionId` to 0. |
| `renounceOwnership()` | `JBOwnableOverrides` | Permanently gives up ownership. Sets both `owner` and `projectId` to zero. Irreversible -- no one can call `onlyOwner` functions afterward. |
| `setPermissionId(uint8 permissionId)` | `JBOwnableOverrides` | Sets which `JBPermissions` permission ID grants delegated owner access. Only callable by the current owner. |

### Internal

| Function | Contract | What it does |
|----------|----------|--------------|
| `_checkOwner()` | `JBOwnableOverrides` | Resolves the owner, then calls `_requirePermissionFrom(account, projectId, permissionId)`. Used by the `onlyOwner` modifier. |
| `_transferOwnership(address newOwner, uint88 projectId)` | `JBOwnableOverrides` | Core transfer logic. Reverts if both `newOwner` and `projectId` are non-zero. Updates `jbOwner` struct and resets `permissionId` to 0. Calls `_emitTransferEvent`. No access restriction. |
| `_transferOwnership(address newOwner)` | `JBOwnableOverrides` | Convenience overload that calls `_transferOwnership(newOwner, 0)`. Exists for drop-in compatibility with OpenZeppelin `Ownable`. |
| `_setPermissionId(uint8 permissionId)` | `JBOwnableOverrides` | Sets `jbOwner.permissionId` and emits `PermissionIdChanged`. No access restriction -- meant for internal use. |
| `_emitTransferEvent(address previousOwner, address newOwner, uint88 newProjectId)` | `JBOwnable` (overrides abstract in `JBOwnableOverrides`) | Emits `OwnershipTransferred`. Resolves `newProjectId` to the current NFT holder via `PROJECTS.ownerOf()`. Override this in `JBOwnableOverrides` subclasses if you need custom transfer event behavior (e.g., deploying before a project NFT is minted). |

## Immutable State

| Variable | Type | Description |
|----------|------|-------------|
| `PROJECTS` | `IJBProjects` | The `JBProjects` ERC-721 contract used to resolve project ownership. |
| `PERMISSIONS` | `IJBPermissions` | Inherited from `JBPermissioned`. The `JBPermissions` contract used for delegated access checks. |

## Key Types

| Type | Fields | Storage |
|------|--------|---------|
| `JBOwner` | `address owner` (160 bits), `uint88 projectId` (88 bits), `uint8 permissionId` (8 bits) | Single 256-bit slot. `owner` and `projectId` are mutually exclusive (both non-zero is invalid). |

## Events

| Event | Fields | When |
|-------|--------|------|
| `OwnershipTransferred` | `address indexed previousOwner`, `address indexed newOwner`, `address caller` | Every ownership change (transfer, project transfer, renounce). |
| `PermissionIdChanged` | `uint8 newId`, `address caller` | When `setPermissionId` or `_setPermissionId` is called. |

## Errors

| Error | When |
|-------|------|
| `JBOwnableOverrides_InvalidNewOwner()` | Constructor gets both zero owner and zero projectId. `transferOwnership(address(0))`. `transferOwnershipToProject(0)` or `transferOwnershipToProject(id > type(uint88).max)`. `_transferOwnership` called with both non-zero owner and non-zero projectId. |
| `JBOwnableOverrides_ProjectDoesNotExist()` | `transferOwnershipToProject(id)` where `id > PROJECTS.count()`. |

## Integration Points

| Dependency | Import | Used For |
|------------|--------|----------|
| `nana-core-v6` | `IJBPermissions`, `JBPermissioned` | Permission checks for delegated access via `_requirePermissionFrom` |
| `nana-core-v6` | `IJBProjects` | Resolving project NFT holder as owner via `PROJECTS.ownerOf(projectId)` |
| `@openzeppelin/contracts` | `Context` | `_msgSender()` support for meta-transaction compatibility |

## Gotchas

- **Mutually exclusive ownership modes.** You cannot set both `owner` and `projectId` to non-zero values. The constructor, `transferOwnership`, and `transferOwnershipToProject` all enforce this. `_transferOwnership` reverts with `JBOwnableOverrides_InvalidNewOwner` if both are non-zero.
- **Constructor rejects zero-zero initialization.** If both `initialOwner` and `initialProjectIdOwner` are zero, the constructor reverts. To create an unowned contract, set an initial owner and call `renounceOwnership()` in the constructor body.
- **`permissionId` resets to 0 on every ownership transfer.** This is intentional -- it prevents stale permission delegation from carrying over to new owners. The new owner must explicitly call `setPermissionId()` to re-enable delegated access.
- **Delegated permissions are scoped to the granting address.** When a project NFT is transferred, delegates authorized by the old holder lose access immediately. The new holder must re-grant permissions via `JBPermissions.setPermissionsFor(...)`.
- **ROOT permission (ID 1) always grants access.** `_checkOwner()` delegates to `_requirePermissionFrom` from `JBPermissioned`, which recognizes the ROOT permission (ID 1) as granting access regardless of the configured `permissionId`.
- **`renounceOwnership()` is irreversible.** After renouncing, `owner()` returns `address(0)`, and all `onlyOwner` functions permanently revert. There is no recovery mechanism.
- **`projectId` is `uint88`.** Project IDs above `type(uint88).max` (309,485,009,821,345,068,724,781,055) are rejected by `transferOwnershipToProject`. This constraint enables the `JBOwner` struct to fit in a single storage slot.
- **`transferOwnershipToProject` checks existence.** It compares the project ID against `PROJECTS.count()` and reverts with `JBOwnableOverrides_ProjectDoesNotExist` if the project does not exist, preventing permanent loss of contract control.
- **`owner()` makes an external call in project mode.** When `projectId != 0`, `owner()` calls `PROJECTS.ownerOf(projectId)`, which is an external call. This is relevant for gas-sensitive contexts.
- **No ERC2771 support.** Despite inheriting `Context`, `JBOwnable` uses plain `Context._msgSender()` (which returns `msg.sender`), not `ERC2771Context`. A trusted forwarder appending a sender address to calldata has no effect on ownership checks.

## Example: Inherit JBOwnable

```solidity
import {JBOwnable} from "@bananapus/ownable-v6/src/JBOwnable.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";

contract MyHook is JBOwnable {
    constructor(
        IJBPermissions permissions,
        IJBProjects projects,
        uint88 projectId
    ) JBOwnable(permissions, projects, address(0), projectId) {}

    function restrictedAction() external onlyOwner {
        // Only the project NFT holder (or delegated addresses) can call this.
    }
}
```

## Example: Address-Owned Contract

```solidity
contract MyContract is JBOwnable {
    constructor(
        IJBPermissions permissions,
        IJBProjects projects,
        address initialOwner
    ) JBOwnable(permissions, projects, initialOwner, 0) {}

    function adminFunction() external onlyOwner {
        // Only initialOwner (or delegated addresses) can call this.
    }
}
```

## Example: Override _emitTransferEvent

If you need to deploy a `JBOwnableOverrides`-based contract before the project NFT exists (e.g., the contract is deployed as part of the project creation flow), override `_emitTransferEvent` to handle the case where the project ID is not yet minted:

```solidity
import {JBOwnableOverrides} from "@bananapus/ownable-v6/src/JBOwnableOverrides.sol";

contract MyPreDeployContract is JBOwnableOverrides {
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    constructor(
        IJBPermissions permissions,
        IJBProjects projects,
        address initialOwner,
        uint88 initialProjectIdOwner
    ) JBOwnableOverrides(permissions, projects, initialOwner, initialProjectIdOwner) {}

    function _emitTransferEvent(
        address previousOwner,
        address newOwner,
        uint88 newProjectId
    ) internal override {
        // Custom logic -- e.g., skip ownerOf() if the project NFT is not yet minted.
        emit OwnershipTransferred({
            previousOwner: previousOwner,
            newOwner: newProjectId == 0 ? newOwner : address(0), // Resolve later.
            caller: msg.sender
        });
    }
}
```
