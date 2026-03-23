# User Journeys -- nana-ownable-v6

Concrete end-to-end flows through the JBOwnable system. Each journey traces the exact function calls, state changes, events, and edge cases.

---

## Journey 1: Deploy a Project-Owned Contract

**Entry point**: `new MyHook(IJBPermissions permissions, IJBProjects projects, address(0), uint88 projectId)`

**Who can call**: Anyone (deployment is permissionless).

**Parameters**:
- `permissions` -- The `IJBPermissions` contract used for delegated access checks
- `projects` -- The `IJBProjects` contract used to resolve project NFT ownership
- `initialOwner` -- Set to `address(0)` because ownership is project-based
- `initialProjectIdOwner` -- The ID of the Juicebox project whose NFT holder becomes the owner

**State changes**:
1. `PROJECTS` immutable set to `projects`
2. Constructor validates `initialProjectIdOwner != 0` AND `address(projects) != address(0)` (reverts with `JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner` if violated)
3. `_transferOwnership(address(0), projectId)` executes:
   - Sets `jbOwner = JBOwner({owner: address(0), projectId: projectId, permissionId: 0})`
   - Calls `_emitTransferEvent(address(0), address(0), projectId)`
4. `owner()` now resolves dynamically via `PROJECTS.ownerOf(projectId)`

**Events**: `OwnershipTransferred(previousOwner: address(0), newOwner: PROJECTS.ownerOf(projectId), caller: msg.sender)`

**Edge cases**:
- If the project does not exist (ID > `PROJECTS.count()`), the constructor still succeeds -- the existence check is only enforced in `transferOwnershipToProject`, not the constructor. The deployer presumably knows the project exists.
- `owner()` returns the current NFT holder dynamically. If the NFT is transferred, ownership automatically follows -- no on-chain update to the JBOwnable contract is needed.

   - `initialOwner = address(0)` because ownership is project-based
   - `initialProjectIdOwner = projectId`

2. **Constructor execution in `JBOwnableOverrides`**

   - Stores `PROJECTS = projects` (immutable)
   - Guard: reverts with `JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner` if `initialProjectIdOwner != 0` and `address(projects) == address(0)` — passes (projects is non-zero)
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
- If the project does not exist, the constructor reverts. `_emitTransferEvent` calls `PROJECTS.ownerOf(projectId)` without try-catch, which reverts for non-existent tokens. This is intentional — it prevents deploying an ownable contract tied to a non-existent project.

---

## Journey 2: Transfer Ownership to a Different Address

**Entry point**: `JBOwnableOverrides.transferOwnership(address newOwner)`

**Who can call**: The current owner (resolved via `PROJECTS.ownerOf()` if project-owned, or `jbOwner.owner` if address-owned), or any address with the configured `permissionId` (or ROOT) via `JBPermissions`.

**Parameters**:
- `newOwner` -- The address to transfer ownership to (must not be `address(0)`)

### Steps

1. **`_checkOwner()` validates the caller**

   - Resolves the current owner (via `PROJECTS.ownerOf()` if project-owned, or `jbOwner.owner` if address-owned)
   - Calls `_requirePermissionFrom(resolvedOwner, projectId, permissionId)`
   - Passes if `msg.sender == resolvedOwner` OR `msg.sender` has the required permission

2. **Owner calls `transferOwnership(newOwner)`**

   - `newOwner` must not be `address(0)` (reverts with `JBOwnableOverrides_InvalidNewOwner`)

3. **`_transferOwnership(newOwner, 0)` executes the transfer**

   - Records `oldOwner` (resolved from current `jbOwner`)
   - Overwrites `jbOwner = JBOwner({owner: newOwner, projectId: 0, permissionId: 0})`
   - Calls `_emitTransferEvent(oldOwner, newOwner, 0)`

**Events**: `OwnershipTransferred(previousOwner: oldOwner, newOwner: newOwner, caller: msg.sender)`

**Edge cases**:
- If the contract was previously project-owned, `projectId` is now 0 (project ownership is cleared)
- `permissionId` is reset to 0, revoking all previously delegated permissions. The new owner must call `setPermissionId()` to re-enable delegated access.
- The previous owner (or their delegates) can no longer call `onlyOwner` functions
- `newOwner` can immediately call `onlyOwner` functions without any additional setup

---

## Journey 3: Transfer Ownership to a Juicebox Project

**Entry point**: `JBOwnableOverrides.transferOwnershipToProject(uint256 projectId)`

**Who can call**: The current owner (resolved via `PROJECTS.ownerOf()` if project-owned, or `jbOwner.owner` if address-owned), or any address with the configured `permissionId` (or ROOT) via `JBPermissions`.

The target project exists (ID <= `PROJECTS.count()`). The caller is the current owner or has adequate permissions.

### Steps

1. **`_checkOwner()` validates the caller** (same as Journey 2, Step 1)

2. **Owner calls `transferOwnershipToProject(projectId)`**

   - Validates: `projectId != 0` (reverts with `JBOwnableOverrides_InvalidNewOwner`)
   - Validates: `projectId <= type(uint88).max` (reverts with `JBOwnableOverrides_InvalidNewOwner`)
   - Validates: `projectId <= PROJECTS.count()` (reverts with `JBOwnableOverrides_ProjectDoesNotExist`)

3. **`_transferOwnership(address(0), uint88(projectId))` executes the transfer**

**State changes**:
1. `_checkOwner()` validates the caller
2. Validates `projectId != 0` and `projectId <= type(uint88).max` (reverts with `JBOwnableOverrides_InvalidNewOwner`)
3. Validates `projectId <= PROJECTS.count()` (reverts with `JBOwnableOverrides_ProjectDoesNotExist`)
4. `_transferOwnership(address(0), uint88(projectId))` executes:
   - Records `oldOwner` (resolved from current `jbOwner`)
   - Overwrites `jbOwner = JBOwner({owner: address(0), projectId: uint88(projectId), permissionId: 0})`
   - Calls `_emitTransferEvent(oldOwner, address(0), uint88(projectId))`

**Events**: `OwnershipTransferred(previousOwner: oldOwner, newOwner: PROJECTS.ownerOf(projectId), caller: msg.sender)`

**Edge cases**:
- The project existence check (`projectId <= PROJECTS.count()`) prevents transferring to a nonexistent project
- The `uint88` cast does not truncate (the preceding `type(uint88).max` check ensures this)
- `permissionId` is reset to 0 on transfer. The new project owner must call `setPermissionId()` to configure delegation.
- If the project NFT is subsequently burned (hypothetically), `owner()` returns `address(0)` and the contract is effectively renounced

---

## Journey 4: Delegate Access via Permission ID

**Entry point**: `JBOwnableOverrides.setPermissionId(uint8 permissionId)`

**Who can call**: The current owner (resolved via `PROJECTS.ownerOf()` if project-owned, or `jbOwner.owner` if address-owned), or any address with the currently configured `permissionId` (or ROOT) via `JBPermissions`.

**Parameters**:
- `permissionId` -- The new permission ID to use for `onlyOwner` access delegation

**State changes**:
1. `_checkOwner()` validates the caller
2. `_setPermissionId(permissionId)` writes `jbOwner.permissionId = permissionId`

**Events**: `PermissionIdChanged(newId: permissionId, caller: msg.sender)`

**Granting the permission to operators** (external step, not on JBOwnable):
- The owner calls `permissions.setPermissionsFor(account, JBPermissionsData({operator: operatorAddress, projectId: projectId, permissionIds: [permissionId]}))` on the `JBPermissions` contract
- Operators can then call any `onlyOwner` function. `_checkOwner()` resolves the owner and calls `_requirePermissionFrom(resolvedOwner, projectId, permissionId)`, which passes if the operator has the matching permission.

**Edge cases**:
- `permissionId == 0` effectively disables delegation (permission ID 0 cannot be set in `JBPermissions`). Only the owner (or ROOT holders) can call `onlyOwner` functions.
- If the owner transfers ownership, `permissionId` resets to 0. The new owner must re-configure delegation.
- ROOT (permission ID 1) always grants access regardless of the configured `permissionId`. This is a feature of `JBPermissioned`, not specific to `JBOwnable`.
- The operator's access is not stored on the JBOwnable contract -- it lives in JBPermissions. Changing the `permissionId` on JBOwnable instantly changes which JBPermissions grants are recognized.

---

## Journey 5: Renounce Ownership

**Entry point**: `JBOwnableOverrides.renounceOwnership()`

**Who can call**: The current owner (resolved via `PROJECTS.ownerOf()` if project-owned, or `jbOwner.owner` if address-owned), or any address with the configured `permissionId` (or ROOT) via `JBPermissions`.

**Parameters**: None.

**State changes**:
1. `_checkOwner()` validates the caller
2. `_transferOwnership(address(0), 0)` executes:
   - Records `oldOwner` (resolved from current `jbOwner`)
   - Overwrites `jbOwner = JBOwner({owner: address(0), projectId: 0, permissionId: 0})`
   - Calls `_emitTransferEvent(oldOwner, address(0), 0)`

**Events**: `OwnershipTransferred(previousOwner: oldOwner, newOwner: address(0), caller: msg.sender)`

**Edge cases**:
- After renouncing, `transferOwnership`, `transferOwnershipToProject`, `setPermissionId`, and `renounceOwnership` all revert
- There is no recovery mechanism. No admin backdoor. No timelock. Renouncement is permanent.
- A second call to `renounceOwnership()` also reverts (because `_checkOwner()` fails)
- Even ROOT holders cannot act as owner after renouncement, because `_requirePermissionFrom(address(0), 0, 0)` does not recognize ROOT as a valid bypass when the account is `address(0)`

---

## Journey 6: Implicit Renouncement via Project NFT Burn

**Actor**: None (system behavior).

**Who can call**: N/A -- this is an emergent behavior, not a direct function call.

**Parameters**: None.

**Precondition**: The contract is project-owned (`jbOwner.projectId != 0`). The project NFT is burned or otherwise invalidated (note: JBProjects V6 has no burn function, so this is a defensive scenario).

**State changes**:
1. `PROJECTS.ownerOf(projectId)` starts reverting (ERC-721 `ownerOf` reverts for burned tokens)
2. `owner()` catches the revert via try-catch and returns `address(0)`
3. `_checkOwner()` catches the revert and resolves owner to `address(0)`, causing `_requirePermissionFrom(address(0), projectId, permissionId)` to fail for any `msg.sender`

**Events**: None (no transaction occurs on the JBOwnable contract).

2. **`owner()` catches the revert and returns `address(0)`**

   - The try-catch in `owner()` returns `address(0)` when `ownerOf` reverts

3. **`_checkOwner()` catches the revert and resolves owner to `address(0)`**

   - `_requirePermissionFrom(address(0), projectId, permissionId)` is called
   - No `msg.sender` can equal `address(0)`, so the check always fails

### Result

The contract is effectively renounced without anyone calling `renounceOwnership()`. All `onlyOwner` functions permanently revert. The `jbOwner` struct still contains the old `projectId`, but it has no practical effect.

### What to verify

- If re-minting an NFT with the same ID were possible, it would restore ownership (the `jbOwner.projectId` is still set). However, JBProjects V6 has no burn or re-mint mechanism, so this scenario is purely hypothetical.
- The `jbOwner` struct is NOT cleared in this scenario -- it still shows the old `projectId`. Only the resolved owner is `address(0)`.
- This behavior is consistent between `owner()` and `_checkOwner()` (both use the same try-catch pattern).
