# Administration

## At A Glance

| Item | Details |
| --- | --- |
| Scope | Ownership resolution primitive used by downstream repos |
| Control posture | Primitive only; control depends on the inheriting contract |
| Highest-risk actions | Transferring ownership to the wrong address/project, enabling the wrong project-scoped permission ID, and misreading delegated-permission lifetime |
| Recovery posture | Recovery depends on the inheriting contract and the still-recognized current owner |

## Purpose

`nana-ownable-v6` does not add a new admin surface by itself. It defines how ownership is resolved for other repos. The important question is how a contract's `owner()` is determined and how delegated permission IDs behave across ownership transfers.

## Control Model

- ownership can be address-based or project-based
- address-based ownership is direct-owner-only
- project-owned delegated operator checks run through `JBPermissions`
- transfer and renounce semantics are part of the primitive
- explicit ownership transfers reset delegated permission state
- project NFT transfers leave `permissionId` stored but ineffective while the current owner differs from
  `_permissionOwner`

## Roles

| Role | How Assigned | Scope | Notes |
| --- | --- | --- | --- |
| Direct owner | Stored owner address | Per contract | Standard `Ownable`-like control |
| Project owner | Holder of the referenced project NFT | Per contract | Dynamic ownership resolution |
| Delegated operator | `JBPermissions` grant with the configured permission ID | Per project-owned contract and project | Only if the contract is project-owned and the owner enables it |

## Privileged Surfaces

The meaningful control surfaces are inherited by downstream contracts:

- `setPermissionId(...)`
- `transferOwnership(...)`
- `transferOwnershipToProject(...)`
- `renounceOwnership()`
- `onlyOwner` checks that resolve either the direct owner or the current project NFT holder

## Immutable And One-Way

- project ownership changes dynamically with project NFT transfers
- delegated permission ID resets on explicit ownership transfer or renounce
- project NFT transfer can make a stored permission ID stale without clearing it from storage
- renouncing ownership is final unless the inheriting contract adds a separate recovery path

## Operational Notes

- treat project-based ownership as live routing, not a snapshot
- distinguish explicit ownership transfer from project NFT transfer: the former clears `permissionId`, the latter only
  changes whether the stored ID is effective
- revoke old `JBPermissions` grants when a project NFT round trips back to a prior owner
- treat `setPermissionId(...)` as a real authority change for project-owned contracts because it rewires which delegated permission bit counts as owner access
- expect `setPermissionId(nonzero)` to revert while a contract is address-owned
- review the inheriting contract, not just this primitive, to understand the full admin surface

## Machine Notes

- do not conclude authority from this repo alone; follow the inheriting contract's `onlyOwner` surfaces
- treat explicit ownership transfer as changing both owner identity and usable delegated permission ID
- treat project NFT transfer as changing owner identity while preserving stored `permissionId`
- if the contract is project-owned and the current permission ID is undocumented, inspect `jbOwner.permissionId` before reasoning about delegated owner access
- if a downstream repo uses project-based ownership, re-evaluate owner resolution after every project NFT transfer

## Recovery

- this primitive has no protocol-wide recovery surface
- if ownership was transferred to the wrong project or address, recovery depends on the inheriting contract still recognizing the current owner

## Admin Boundaries

- this repo does not create a new permission namespace
- it cannot make an inheriting contract safer than that contract's own privileged functions
- it keeps address-owned contracts direct-owner-only
- it clears delegated operators only on explicit ownership-transfer paths

## Source Map

- `src/JBOwnable.sol`
- `src/JBOwnableOverrides.sol`
- `src/structs/JBOwner.sol`
- `test/OwnableInvariantTests.sol`
- `test/OwnableEdgeCases.t.sol`
- `test/regression/BurnLockProtection.t.sol`
