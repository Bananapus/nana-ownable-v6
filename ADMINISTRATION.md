# Administration

Admin privileges and their scope in nana-ownable-v6.

## Roles

| Role | Who | How Access Is Determined |
|------|-----|------------------------|
| **Direct Owner** | An EOA or contract stored in `JBOwner.owner` | Used when `JBOwner.projectId == 0`. Set at construction or via `transferOwnership(address)`. |
| **Project Owner** | The holder of the `JBProjects` ERC-721 for `JBOwner.projectId` | Used when `JBOwner.projectId != 0`. Resolved dynamically via `PROJECTS.ownerOf(projectId)` on every call. |
| **Permission Delegate** | Any address granted `JBOwner.permissionId` through `JBPermissions` | The owner (direct or project) calls `JBPermissions.setPermissionsFor(...)` to grant `permissionId` to an operator. That operator then passes the `_checkOwner()` / `_requirePermissionFrom()` check. |

Only one of Direct Owner or Project Owner is active at a time, never both. Permission Delegates extend whichever mode is active.

## Privileged Functions

### JBOwnableOverrides (abstract base)

| Function | Required Role | Permission ID | Scope | What It Does |
|----------|--------------|---------------|-------|--------------|
| `renounceOwnership()` | Owner or delegate | `jbOwner.permissionId` | Per-contract | Sets `owner` to `address(0)` and `projectId` to `0`. Permanently disables all `onlyOwner`-guarded functions. Irreversible. |
| `setPermissionId(uint8)` | Owner or delegate | `jbOwner.permissionId` | Per-contract | Changes which permission ID grants owner-equivalent access via `JBPermissions`. Resets the delegation surface -- previous delegates with the old ID lose access. |
| `transferOwnership(address)` | Owner or delegate | `jbOwner.permissionId` | Per-contract | Transfers ownership to a new address. Resets `projectId` to `0` and `permissionId` to `0`. The new owner must call `setPermissionId()` to re-enable delegation. |
| `transferOwnershipToProject(uint256)` | Owner or delegate | `jbOwner.permissionId` | Per-contract | Transfers ownership to a Juicebox project. Resets `owner` to `address(0)` and `permissionId` to `0`. Validates that the project exists (`projectId <= PROJECTS.count()`). |

### JBOwnable (concrete contract)

`JBOwnable` inherits all functions above and adds no additional privileged functions. It provides the `onlyOwner` modifier for use by inheriting contracts.

Any contract that inherits `JBOwnable` and applies the `onlyOwner` modifier to its own functions effectively creates additional privileged functions gated by the same ownership and permission model described here.

## Ownership Model

JBOwnable bridges Juicebox project ownership to the OpenZeppelin `Ownable` pattern through the `JBOwner` struct:

```
JBOwner {
    address owner;        // Direct owner address (when projectId == 0)
    uint88  projectId;    // JB project whose NFT holder is owner (when != 0)
    uint8   permissionId; // Permission ID for delegation via JBPermissions
}
```

**Resolution logic** (in `_checkOwner()` and `owner()`):

1. If `projectId != 0`, the owner is `PROJECTS.ownerOf(projectId)` -- resolved dynamically on every call. If `ownerOf()` reverts (e.g., hypothetical NFT burn), the resolved owner becomes `address(0)`, effectively renouncing the contract.
2. If `projectId == 0`, the owner is `JBOwner.owner` directly.
3. In both cases, `_checkOwner()` calls `_requirePermissionFrom(resolvedOwner, projectId, permissionId)`, which passes if `msg.sender` is the resolved owner OR has the configured `permissionId` granted through `JBPermissions`.

**Permission delegation** uses the nana-core `JBPermissions` contract. The owner calls `JBPermissions.setPermissionsFor(...)` to grant `permissionId` to an operator address. That operator can then call any `onlyOwner` function on this contract. The ROOT permission (ID 1) in `JBPermissions` grants all permission IDs, including whatever `permissionId` is configured here.

**Ownership transfer resets `permissionId` to 0.** This prevents the previous owner's delegates from retaining access after a transfer. The new owner must explicitly call `setPermissionId()` to configure delegation.

## Immutable Configuration

| Property | Set At | Can Change? |
|----------|--------|-------------|
| `PERMISSIONS` (IJBPermissions) | Construction (via `JBPermissioned`) | No -- immutable |
| `PROJECTS` (IJBProjects) | Construction | No -- immutable |

The `JBPermissions` and `JBProjects` contract references are baked in at deploy time and cannot be changed. If either contract is upgraded or replaced, the `JBOwnable` instance must be redeployed.

## Admin Boundaries

What admins **cannot** do:

- **Change the `PERMISSIONS` or `PROJECTS` contracts.** These are immutable references set at construction.
- **Set both `owner` and `projectId` simultaneously.** The `_transferOwnership` internal function reverts if both are non-zero.
- **Transfer to `address(0)` via `transferOwnership()`.** This reverts with `JBOwnableOverrides_InvalidNewOwner`. Use `renounceOwnership()` instead.
- **Transfer to a non-existent project.** `transferOwnershipToProject()` checks `projectId <= PROJECTS.count()` and reverts if the project does not exist.
- **Transfer to `projectId` 0 via `transferOwnershipToProject()`.** Reverts with `JBOwnableOverrides_InvalidNewOwner`.
- **Transfer to `projectId` exceeding `uint88`.** Reverts with `JBOwnableOverrides_InvalidNewOwner`.
- **Undo `renounceOwnership()`.** Once ownership is renounced, all `onlyOwner` functions are permanently disabled. There is no recovery mechanism.
- **Bypass `JBPermissions` for delegation.** Permission delegation is exclusively handled through the external `JBPermissions` contract; `JBOwnable` itself has no operator registry.
- **Prevent project NFT transfers from changing ownership.** When owned by a project, whoever holds the `JBProjects` ERC-721 is the owner. There is no veto or lock mechanism within `JBOwnable`.
