# Administration

## At A Glance

| Item | Details |
| --- | --- |
| Scope | Ownership resolution primitive used by downstream repos |
| Control posture | Primitive only; control depends on the inheriting contract |
| Highest-risk actions | Transferring ownership to the wrong address or project and assuming delegated operators survive transfer |
| Recovery posture | Recovery depends on the inheriting contract and the still-recognized current owner |

## Purpose

`nana-ownable-v6` does not add a new admin surface by itself. It defines how ownership is resolved for other repos. The important question is how a contract's `owner()` is determined and how delegated permission IDs behave across ownership transfers.

## Control Model

- ownership can be address-based or project-based
- delegated operator checks run through `JBPermissions`
- transfer and renounce semantics are part of the primitive
- delegated permission resets on ownership transfer

## Roles

| Role | How Assigned | Scope | Notes |
| --- | --- | --- | --- |
| Direct owner | Stored owner address | Per contract | Standard `Ownable`-like control |
| Project owner | Holder of the referenced project NFT | Per contract | Dynamic ownership resolution |
| Delegated operator | `JBPermissions` grant with the configured permission ID | Per contract and project | Only if the inheriting contract enables it |

## Privileged Surfaces

The meaningful control surfaces are inherited by downstream contracts:

- `setPermissionId(...)`
- `transferOwnership(...)`
- `transferOwnershipToProject(...)`
- `renounceOwnership()`
- `onlyOwner` checks that resolve either the direct owner or the current project NFT holder

## Immutable And One-Way

- project ownership changes dynamically with project NFT transfers
- delegated permission ID resets on ownership transfer
- renouncing ownership is final unless the inheriting contract adds a separate recovery path

## Operational Notes

- treat project-based ownership as live routing, not a snapshot
- do not assume an operator permission survives ownership transfer
- treat `setPermissionId(...)` as a real authority change because it rewires which delegated permission bit counts as owner access
- review the inheriting contract, not just this primitive, to understand the full admin surface

## Machine Notes

- do not conclude authority from this repo alone; follow the inheriting contract's `onlyOwner` surfaces
- treat ownership transfer as potentially changing both the owner identity and the usable delegated permission ID
- if the current permission ID is undocumented, inspect `jbOwner.permissionId` before reasoning about delegated owner access
- if a downstream repo uses project-based ownership, re-evaluate owner resolution after every project NFT transfer

## Recovery

- this primitive has no protocol-wide recovery surface
- if ownership was transferred to the wrong project or address, recovery depends on the inheriting contract still recognizing the current owner

## Admin Boundaries

- this repo does not create a new permission namespace
- it cannot make an inheriting contract safer than that contract's own privileged functions
- it cannot preserve delegated operators across ownership transfer by default

## Source Map

- `src/JBOwnable.sol`
- `src/JBOwnableOverrides.sol`
- `src/structs/JBOwner.sol`
- `test/OwnableInvariantTests.sol`
- `test/OwnableEdgeCases.t.sol`
- `test/regression/BurnLockProtection.t.sol`
