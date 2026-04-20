# Administration

## At A Glance

| Item | Details |
| --- | --- |
| Scope | Ownership resolution primitive used by downstream repos |
| Control posture | Primitive only; control depends on the inheriting contract |
| Highest-risk actions | Transferring ownership to the wrong address or project and assuming delegated operators survive transfer |
| Recovery posture | Recovery depends on the inheriting contract and the still-recognized current owner |

## Purpose

`nana-ownable-v6` does not introduce a new admin surface by itself. It defines how ownership is resolved for other repos. The important control question is how a contract's `owner()` is determined and how delegated permission IDs behave across ownership transfers.

## Control Model

- Ownership can be address-based or project-based.
- Delegated operator checks run through `JBPermissions`.
- Transfer and renounce semantics are part of the primitive.
- Permission delegation resets on ownership transfer.

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

- Project ownership changes dynamically with project NFT transfers.
- Delegated permission ID resets on ownership transfer.
- Renouncing ownership is final unless the inheriting contract adds a separate recovery path.

## Operational Notes

- Treat project-based ownership as live routing, not a snapshot.
- Do not assume an operator permission survives ownership transfer.
- Treat `setPermissionId(...)` as a real authority change because it rewires which delegated permission bit counts as owner access.
- Review the inheriting contract, not just this primitive, to understand the full admin surface.

## Machine Notes

- Do not conclude authority from this repo alone; follow the inheriting contract's `onlyOwner` surfaces.
- Treat ownership transfer as potentially changing both the owner identity and the usable delegated permission ID.
- If the current permission ID is undocumented, inspect `jbOwner.permissionId` before reasoning about delegated owner access.
- If a downstream repo uses project-based ownership, re-evaluate owner resolution after every project NFT transfer.

## Recovery

- This primitive has no protocol-wide recovery surface.
- If ownership was transferred to the wrong project or address, recovery depends on the inheriting contract still recognizing the current owner.

## Admin Boundaries

- This repo does not create a new permission namespace.
- It cannot make an inheriting contract safer than that contract's own privileged functions.
- It cannot preserve delegated operators across ownership transfer by default.

## Source Map

- `src/JBOwnable.sol`
- `src/JBOwnableOverrides.sol`
- `src/structs/JBOwner.sol`
- `test/OwnableInvariantTests.sol`
- `test/OwnableEdgeCases.t.sol`
- `test/regression/BurnLockProtection.t.sol`
