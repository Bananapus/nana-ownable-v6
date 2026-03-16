# User Journeys -- nana-ownable-v6

Concrete end-to-end flows through the JBOwnable system. Each journey traces the exact function calls, state changes, and external interactions.

## Journey 1: Deploy a Project-Owned Contract

**Actor:** Protocol developer deploying a hook or extension that should be owned by a Juicebox project.
**Goal:** Create a contract where the project NFT holder has owner access.

### Precondition

A Juicebox project exists with ID `projectId`. The `JBProjects` and `JBPermissions` contracts are deployed.

### Steps

1. **Developer deploys a contract inheriting `JBOwnable`**

   ```solidity
   new MyHook(permissions, projects, address(0), projectId)
   ```

   - `initialOwner = address(0)` because ownership is project-based
   - `initialProjectIdOwner = projectId`

2. **Constructor execution in `JBOwnableOverrides`**

   - Stores `PROJECTS = projects` (immutable)
   - Validates: `initialProjectIdOwner != 0` AND `address(projects) != address(0)` -- passes
   - Validates: not both zero (passes because `initialProjectIdOwner != 0`)
   - Calls `_transferOwnership(address(0), projectId)`:
     - Sets `jbOwner = JBOwner({owner: address(0), projectId: projectId, permissionId: 0})`
     - Calls `_emitTransferEvent(address(0), address(0), projectId)`
   - In `JBOwnable._emitTransferEvent`: emits `OwnershipTransferred(address(0), PROJECTS.ownerOf(projectId), msg.sender)`

3. **Ownership is now live**

   - `owner()` calls `PROJECTS.ownerOf(projectId)` and returns the current NFT holder
   - `_checkOwner()` validates `msg.sender` against the NFT holder (or permission delegates)

### Result

The contract is owned by whichever address holds the project NFT. If the NFT is transferred, ownership automatically follows -- no on-chain update to the JBOwnable contract is needed.

### What to verify

- `jbOwner.owner == address(0)` and `jbOwner.projectId == projectId` after construction.
- `jbOwner.permissionId == 0` (no delegated access until explicitly configured).
- `owner()` returns the current NFT holder, not a cached value.
- If the project does not exist (ID > `PROJECTS.count()`), the constructor still succeeds -- the existence check is only enforced in `transferOwnershipToProject`, not the constructor. Verify whether this is safe (the deployer presumably knows the project exists).

---

## Journey 2: Transfer Ownership to a Different Address

**Actor:** Current owner (direct address or project NFT holder).
**Goal:** Transfer ownership from the current owner to a new direct address.

### Precondition

The caller is the current owner or has the configured `permissionId` (or ROOT) via `JBPermissions`.

### Steps

1. **Owner calls `transferOwnership(newOwner)`**

   - `newOwner` must not be `address(0)` (reverts with `JBOwnableOverrides_InvalidNewOwner`)

2. **`_checkOwner()` validates the caller**

   - Resolves the current owner (via `PROJECTS.ownerOf()` if project-owned, or `jbOwner.owner` if address-owned)
   - Calls `_requirePermissionFrom(resolvedOwner, projectId, permissionId)`
   - Passes if `msg.sender == resolvedOwner` OR `msg.sender` has the required permission

3. **`_transferOwnership(newOwner, 0)` executes the transfer**

   - Records `oldOwner` (resolved from current `jbOwner`)
   - Overwrites `jbOwner = JBOwner({owner: newOwner, projectId: 0, permissionId: 0})`
   - Calls `_emitTransferEvent(oldOwner, newOwner, 0)`

4. **`_emitTransferEvent` in `JBOwnable`**

   - Since `newProjectId == 0`: emits `OwnershipTransferred(oldOwner, newOwner, msg.sender)`

### Result

`jbOwner.owner == newOwner`, `jbOwner.projectId == 0`, `jbOwner.permissionId == 0`. The new owner must call `setPermissionId()` to re-enable delegated access.

### What to verify

- If the contract was previously project-owned, `projectId` is now 0 (project ownership is cleared).
- `permissionId` is reset to 0, revoking all previously delegated permissions.
- The previous owner (or their delegates) can no longer call `onlyOwner` functions.
- `newOwner` can immediately call `onlyOwner` functions without any additional setup.

---

## Journey 3: Transfer Ownership to a Juicebox Project

**Actor:** Current owner (direct address or project NFT holder).
**Goal:** Transfer ownership from the current owner to a Juicebox project, so the NFT holder becomes the new owner.

### Precondition

The target project exists (ID <= `PROJECTS.count()`). The caller is the current owner or has adequate permissions.

### Steps

1. **Owner calls `transferOwnershipToProject(projectId)`**

   - Validates: `projectId != 0` (reverts with `JBOwnableOverrides_InvalidNewOwner`)
   - Validates: `projectId <= type(uint88).max` (reverts with `JBOwnableOverrides_InvalidNewOwner`)
   - Validates: `projectId <= PROJECTS.count()` (reverts with `JBOwnableOverrides_ProjectDoesNotExist`)

2. **`_checkOwner()` validates the caller** (same as Journey 2, Step 2)

3. **`_transferOwnership(address(0), uint88(projectId))` executes the transfer**

   - Records `oldOwner` (resolved from current `jbOwner`)
   - Overwrites `jbOwner = JBOwner({owner: address(0), projectId: uint88(projectId), permissionId: 0})`
   - Calls `_emitTransferEvent(oldOwner, address(0), uint88(projectId))`

4. **`_emitTransferEvent` in `JBOwnable`**

   - Since `newProjectId != 0`: emits `OwnershipTransferred(oldOwner, PROJECTS.ownerOf(projectId), msg.sender)`

### Result

`jbOwner.owner == address(0)`, `jbOwner.projectId == projectId`, `jbOwner.permissionId == 0`. The project NFT holder is now the owner. Ownership dynamically follows NFT transfers.

### What to verify

- The project existence check (`projectId <= PROJECTS.count()`) prevents transferring to a nonexistent project.
- The `uint88` cast does not truncate (the preceding `type(uint88).max` check ensures this).
- If the project NFT is subsequently burned (hypothetically), `owner()` returns `address(0)` and the contract is effectively renounced.

---

## Journey 4: Delegate Access via Permission ID

**Actor:** Current owner.
**Goal:** Allow additional addresses to call `onlyOwner` functions through the JBPermissions system.

### Precondition

The contract has an owner. The owner wants to delegate access to one or more operators.

### Steps

1. **Owner calls `setPermissionId(permissionId)`**

   - `_checkOwner()` validates the caller
   - `_setPermissionId(permissionId)` writes `jbOwner.permissionId = permissionId`
   - Emits `PermissionIdChanged(permissionId, msg.sender)`

2. **Owner grants the permission to operators via JBPermissions**

   - `permissions.setPermissionsFor(account, JBPermissionsData({operator: operatorAddress, projectId: projectId, permissionIds: [permissionId]}))`
   - This is an external call on the JBPermissions contract, not on the JBOwnable contract

3. **Operator calls an `onlyOwner` function**

   - `_checkOwner()` resolves the owner and calls `_requirePermissionFrom(resolvedOwner, projectId, permissionId)`
   - `JBPermissioned._requirePermissionFrom` checks `JBPermissions.hasPermission(msg.sender, resolvedOwner, projectId, permissionId)` -- passes

### Result

The operator can call any function protected by `onlyOwner` on this contract. The permission is scoped to the owner's account and project ID.

### What to verify

- `permissionId == 0` effectively disables delegation (permission ID 0 cannot be set in `JBPermissions`). Only the owner (or ROOT holders) can call `onlyOwner` functions.
- If the owner transfers ownership, `permissionId` resets to 0. The new owner must re-configure delegation.
- ROOT (permission ID 1) always grants access regardless of the configured `permissionId`. This is a feature of `JBPermissioned`, not specific to `JBOwnable`.
- The operator's access is not stored on the JBOwnable contract -- it lives in JBPermissions. Changing the `permissionId` on JBOwnable instantly changes which JBPermissions grants are recognized.

---

## Journey 5: Renounce Ownership

**Actor:** Current owner.
**Goal:** Permanently give up ownership, making `onlyOwner` functions uncallable.

### Precondition

The caller is the current owner and understands this action is irreversible.

### Steps

1. **Owner calls `renounceOwnership()`**

   - `_checkOwner()` validates the caller

2. **`_transferOwnership(address(0), 0)` executes**

   - Records `oldOwner` (resolved from current `jbOwner`)
   - Overwrites `jbOwner = JBOwner({owner: address(0), projectId: 0, permissionId: 0})`
   - Calls `_emitTransferEvent(oldOwner, address(0), 0)`
   - Emits `OwnershipTransferred(oldOwner, address(0), msg.sender)`

### Result

`jbOwner` is zeroed out. `owner()` returns `address(0)`. All future calls to `_checkOwner()` revert because `_requirePermissionFrom(address(0), 0, 0)` fails for any `msg.sender` (no address equals `address(0)`, and no permission can satisfy the check against a zero-address account).

### What to verify

- After renouncing, `transferOwnership`, `transferOwnershipToProject`, `setPermissionId`, and `renounceOwnership` all revert.
- There is no recovery mechanism. No admin backdoor. No timelock. Renouncement is permanent.
- A second call to `renounceOwnership()` also reverts (because `_checkOwner()` fails).
- Even ROOT holders cannot act as owner after renouncement, because `_requirePermissionFrom(address(0), 0, 0)` does not recognize ROOT as a valid bypass when the account is `address(0)`.

---

## Journey 6: Implicit Renouncement via Project NFT Burn

**Actor:** None (system behavior).
**Goal:** Understand what happens when the project NFT underlying a project-owned contract ceases to exist.

### Precondition

The contract is project-owned (`jbOwner.projectId != 0`). The project NFT is burned or otherwise invalidated (note: JBProjects V6 has no burn function, so this is a defensive scenario).

### Steps

1. **`PROJECTS.ownerOf(projectId)` starts reverting**

   - The ERC-721 `ownerOf` function reverts for burned tokens

2. **`owner()` catches the revert and returns `address(0)`**

   - The try-catch in `owner()` returns `address(0)` when `ownerOf` reverts

3. **`_checkOwner()` catches the revert and resolves owner to `address(0)`**

   - `_requirePermissionFrom(address(0), projectId, permissionId)` is called
   - No `msg.sender` can equal `address(0)`, so the check always fails

### Result

The contract is effectively renounced without anyone calling `renounceOwnership()`. All `onlyOwner` functions permanently revert. The `jbOwner` struct still contains the old `projectId`, but it has no practical effect.

### What to verify

- There is no way to "revive" ownership after the NFT is burned. Even re-minting an NFT with the same ID (if possible) would restore ownership.
- The `jbOwner` struct is NOT cleared in this scenario -- it still shows the old `projectId`. Only the resolved owner is `address(0)`.
- This behavior is consistent between `owner()` and `_checkOwner()` (both use the same try-catch pattern).
