# nana-ownable-v6 Changelog (v5 → v6)

This document describes all changes between `nana-ownable` (v5) and `nana-ownable-v6` (v6).

## Summary

- **Defensive `try-catch` on all `PROJECTS.ownerOf()` calls**: `owner()` now returns `address(0)` instead of reverting for burned/invalid project NFTs — changes observable behavior for callers.
- **New safety validations**: `transferOwnershipToProject()` checks project existence; constructor rejects zero-address `PROJECTS` with project-based ownership.
- **Solidity version pinned**: Changed from floating `^0.8.23` to exact `0.8.26`.

---

## 1. Breaking Changes

### Solidity Version Pinned

All contracts changed from `pragma solidity ^0.8.23` (floating) to `pragma solidity 0.8.26` (pinned). This means v6 can only compile with Solidity 0.8.26 exactly.

**Affected files:** `JBOwnable.sol`, `JBOwnableOverrides.sol`

### Import Paths Updated

All imports reference `@bananapus/core-v6` instead of `@bananapus/core-v5`. Any project depending on `nana-ownable` must also migrate to `nana-core-v6`.

### `owner()` Returns `address(0)` Instead of Reverting for Invalid Projects

In v5, if a project NFT was burned or otherwise invalid, `owner()` would revert because `PROJECTS.ownerOf()` reverts for nonexistent tokens.

In v6, `owner()` wraps the call in `try-catch` and returns `address(0)` if `ownerOf()` reverts. This changes the observable behavior: callers that previously relied on a revert to detect invalid project ownership will now receive `address(0)` instead.

### `_checkOwner()` Behavior Change for Invalid Projects

In v5, `_checkOwner()` would revert with the ERC-721 "nonexistent token" error if the owning project NFT was burned.

In v6, it resolves the owner to `address(0)` via `try-catch` and then passes `address(0)` to `_requirePermissionFrom`. This still causes a revert (no one can authenticate as `address(0)`), but the revert reason changes from an ERC-721 error to a permissions error.

### `transferOwnershipToProject()` Now Validates Project Existence

In v6, `transferOwnershipToProject()` checks `projectId > PROJECTS.count()` and reverts with `JBOwnableOverrides_ProjectDoesNotExist()` if the project has not been created yet. In v5, no such check existed, so ownership could be transferred to a nonexistent project ID.

### Constructor Validates `PROJECTS` Address for Project-Based Ownership

In v6, the constructor reverts with `JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner()` if `initialProjectIdOwner != 0` and `address(projects) == address(0)`. In v5, this combination was silently accepted, which would permanently break ownership resolution since `ownerOf()` calls on `address(0)` would always revert.

### `IJBOwnable` Return Name Changes

The second return value of `jbOwner()` was renamed from `projectOwner` (v5) to `projectId` (v6) in the interface. The type (`uint88`) and position are unchanged, so the ABI is identical, but code referencing the named return will need updating.

Additionally, `PROJECTS()` and `owner()` gained named return values in the interface:

- `PROJECTS()`: `returns (IJBProjects)` (v5) -> `returns (IJBProjects projects)` (v6)
- `owner()`: `returns (address)` (v5) -> `returns (address owner)` (v6)

These are ABI-compatible but change the Solidity-level interface signature.

---

## 2. New Features

### Defensive `try-catch` on All `PROJECTS.ownerOf()` Calls

Every call to `PROJECTS.ownerOf()` in v6 is wrapped in a `try-catch` block. If the call reverts (e.g., burned NFT, broken ERC-721 implementation), the resolved owner falls back to `address(0)`. This applies to:

- `owner()` -- returns `address(0)` instead of reverting.
- `_checkOwner()` -- resolves to `address(0)`, causing a permissions revert.
- `_transferOwnership(address, uint88)` -- resolves old owner to `address(0)` for the transfer event.

### Project Existence Validation on `transferOwnershipToProject()`

`transferOwnershipToProject()` now calls `PROJECTS.count()` to verify the target project exists before transferring ownership, preventing accidental loss of contract control by transferring to a nonexistent project.

### Constructor Guard Against Zero-Address `PROJECTS` with Project Ownership

A new constructor check prevents deploying with `projects == address(0)` when `initialProjectIdOwner != 0`, which would make ownership irrecoverable.

### Comprehensive NatSpec Documentation on `IJBOwnable`

The v6 interface adds full NatSpec documentation for all events, functions, parameters, and return values. The v5 interface had no NatSpec comments at all.

---

## 3. Event Changes

No event signatures changed. Both versions define the same two events with identical parameters and indexing:

- `OwnershipTransferred(address indexed previousOwner, address indexed newOwner, address caller)`
- `PermissionIdChanged(uint8 newId, address caller)`

The only difference is the addition of NatSpec documentation on both events in v6's `IJBOwnable.sol`, and the declaration order was swapped (v5: `PermissionIdChanged` first, then `OwnershipTransferred`; v6: `OwnershipTransferred` first, then `PermissionIdChanged`).

---

## 4. Error Changes

### New Errors

| Error | Contract | Description |
|---|---|---|
| `JBOwnableOverrides_ProjectDoesNotExist()` | `JBOwnableOverrides` | Reverts in `transferOwnershipToProject()` if `projectId > PROJECTS.count()`. |
| `JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner()` | `JBOwnableOverrides` | Reverts in constructor if `initialProjectIdOwner != 0` and `address(projects) == address(0)`. |

### Unchanged Errors

| Error | Status |
|---|---|
| `JBOwnableOverrides_InvalidNewOwner()` | Unchanged -- still used for zero-address owner, zero project ID, and dual-set owner+project scenarios. |

---

## 5. Struct Changes

### `JBOwner` (unchanged)

The struct itself is identical in both versions:

```solidity
struct JBOwner {
    address owner;
    uint88 projectId;
    uint8 permissionId;
}
```

The only difference is the addition of a `// forge-lint: disable-next-line(pascal-case-struct)` comment in v6.

---

## 6. Implementation Changes (Non-Interface)

### `JBOwnableOverrides._checkOwner()` -- Refactored Owner Resolution

**v5:**
```solidity
function _checkOwner() internal view virtual {
    JBOwner memory ownerInfo = jbOwner;
    _requirePermissionFrom({
        account: ownerInfo.projectId == 0 ? ownerInfo.owner : PROJECTS.ownerOf(ownerInfo.projectId),
        projectId: ownerInfo.projectId,
        permissionId: ownerInfo.permissionId
    });
}
```

**v6:**
```solidity
function _checkOwner() internal view virtual {
    JBOwner memory ownerInfo = jbOwner;
    address resolvedOwner;
    if (ownerInfo.projectId == 0) {
        resolvedOwner = ownerInfo.owner;
    } else {
        try PROJECTS.ownerOf(ownerInfo.projectId) returns (address projectOwner) {
            resolvedOwner = projectOwner;
        } catch {
            resolvedOwner = address(0);
        }
    }
    _requirePermissionFrom({
        account: resolvedOwner, projectId: ownerInfo.projectId, permissionId: ownerInfo.permissionId
    });
}
```

The ternary expression is replaced with an explicit `if/else` block and `try-catch` for defensive error handling.

### `JBOwnableOverrides.owner()` -- Try-Catch on Project Lookup

**v5:**
```solidity
return PROJECTS.ownerOf(ownerInfo.projectId);
```

**v6:**
```solidity
try PROJECTS.ownerOf(ownerInfo.projectId) returns (address projectOwner) {
    return projectOwner;
} catch {
    return address(0);
}
```

### `JBOwnableOverrides._transferOwnership(address, uint88)` -- Try-Catch on Old Owner Lookup

**v5:**
```solidity
address oldOwner = ownerInfo.projectId == 0 ? ownerInfo.owner : PROJECTS.ownerOf(ownerInfo.projectId);
```

**v6:**
```solidity
address oldOwner;
if (ownerInfo.projectId == 0) {
    oldOwner = ownerInfo.owner;
} else {
    try PROJECTS.ownerOf(ownerInfo.projectId) returns (address projectOwner) {
        oldOwner = projectOwner;
    } catch {
        oldOwner = address(0);
    }
}
```

### Named Arguments Used Throughout

All internal function calls in v6 use named arguments (e.g., `_transferOwnership({newOwner: initialOwner, projectId: initialProjectIdOwner})`) instead of positional arguments. This is a style-only change with no behavioral impact.

### NatSpec Improvements

- `JBOwnable._emitTransferEvent()`: Incomplete comment in v5 (`"some contracts will try to deploy contracts for a project before"`) is completed in v6 (`"some contracts need to deploy contracts for a project before the project's NFT has been minted, so the transfer event resolves the project's current owner at emission time."`). A new `@dev` comment also explains why this function intentionally does NOT use try-catch (unlike `_transferOwnership`): reverting on a nonexistent new project is desirable to prevent transferring ownership to an invalid project.
- `JBOwnableOverrides._emitTransferEvent()`: Added `@param` tags for `previousOwner`, `newOwner`, and `newProjectId`.
- `renounceOwnership()`, `setPermissionId()`: Changed `@notice This can only be called by the current owner.` to `@dev`.
- `transferOwnership()`, `transferOwnershipToProject()`: Added documentation about `permissionId` being reset to 0 on transfer.
- Constructor `@param initialOwner`: Fixed typo `intialProjectIdOwner` to `initialProjectIdOwner`.

### Comment/Formatting Fixes

- Fixed malformed section header comment in v5 (`custom errors --------------------------//b`) to properly formatted (`custom errors ------------------------- //`).

---

## 7. Migration Table

| v5 | v6 | Change Type |
|---|---|---|
| `pragma solidity ^0.8.23` | `pragma solidity 0.8.26` | Pinned compiler version |
| `@bananapus/core-v5` imports | `@bananapus/core-v6` imports | Dependency upgrade |
| `PROJECTS.ownerOf()` called directly | `try PROJECTS.ownerOf() catch` in `owner()`, `_checkOwner()`, `_transferOwnership()` | Defensive error handling |
| `transferOwnershipToProject()` -- no existence check | Reverts with `JBOwnableOverrides_ProjectDoesNotExist()` if `projectId > PROJECTS.count()` | New validation |
| Constructor allows `projects == address(0)` with `initialProjectIdOwner != 0` | Reverts with `JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner()` | New validation |
| `IJBOwnable.jbOwner()` returns `(address owner, uint88 projectOwner, uint8 permissionId)` | Returns `(address owner, uint88 projectId, uint8 permissionId)` | Return name change (ABI compatible) |
| `IJBOwnable.PROJECTS()` returns `(IJBProjects)`, `owner()` returns `(address)` | Returns `(IJBProjects projects)`, `(address owner)` | Named return values added (ABI compatible) |
| `IJBOwnable` -- no NatSpec | Full NatSpec on all events, functions, params, and returns | Documentation |
| Positional arguments in internal calls | Named arguments throughout | Style only |
| 1 custom error | 3 custom errors (`+ ProjectDoesNotExist`, `+ ZeroAddressProjectsWithProjectOwner`) | New errors |
| `JBOwner` struct | Identical (added forge-lint comment only) | No change |
