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
2. `PERMISSIONS` immutable set to `permissions` (inherited from `JBPermissioned`)
3. Constructor validates `initialProjectIdOwner != 0` AND `address(projects) != address(0)` (reverts with `JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner` if violated)
4. Constructor validates that at least one of `initialOwner` or `initialProjectIdOwner` is non-zero (reverts with `JBOwnableOverrides_InvalidNewOwner` if both are zero)
5. `_transferOwnership(address(0), projectId)` executes:
   - Sets `jbOwner = JBOwner({owner: address(0), projectId: projectId, permissionId: 0})`
   - Calls `_emitTransferEvent(address(0), address(0), projectId)`
6. `owner()` now resolves dynamically via `PROJECTS.ownerOf(projectId)`

**Events**: `OwnershipTransferred(address indexed previousOwner, address indexed newOwner, address caller)` -- emitted as `OwnershipTransferred(address(0), PROJECTS.ownerOf(projectId), msg.sender)`

**Edge cases**:
- If the project does not exist (ID > `PROJECTS.count()`), the constructor still succeeds -- the existence check is only enforced in `transferOwnershipToProject`, not the constructor. If the project NFT has not yet been minted, `PROJECTS.ownerOf()` reverts, and the try-catch in `owner()` returns `address(0)`, effectively locking the contract until the project is minted.
- `owner()` returns the current NFT holder dynamically. If the NFT is transferred, ownership automatically follows -- no on-chain update to the JBOwnable contract is needed.
- Deploying with both `initialOwner == address(0)` and `initialProjectIdOwner == 0` reverts with `JBOwnableOverrides_InvalidNewOwner`. To create an unowned contract, set an owner and call `renounceOwnership()` in the constructor body.

**What to verify**:
- `jbOwner.owner == address(0)` and `jbOwner.projectId == projectId` after construction
- `jbOwner.permissionId == 0` (no delegated access until explicitly configured)
- `owner()` returns the current NFT holder, not a cached value

---

## Journey 1b: Deploy an Address-Owned Contract

**Entry point**: `new MyHook(IJBPermissions permissions, IJBProjects projects, address initialOwner, uint88(0))`

**Who can call**: Anyone (deployment is permissionless).

**Parameters**:
- `permissions` -- The `IJBPermissions` contract used for delegated access checks
- `projects` -- The `IJBProjects` contract (can be `address(0)` when not using project-based ownership)
- `initialOwner` -- The address that becomes the contract owner (must not be `address(0)`)
- `initialProjectIdOwner` -- Set to `0` because ownership is address-based

**State changes**:
1. `PROJECTS` immutable set to `projects`
2. `PERMISSIONS` immutable set to `permissions` (inherited from `JBPermissioned`)
3. Constructor validates that `initialOwner != address(0)` (reverts with `JBOwnableOverrides_InvalidNewOwner` if both `initialOwner` and `initialProjectIdOwner` are zero)
4. `_transferOwnership(initialOwner, 0)` executes:
   - Sets `jbOwner = JBOwner({owner: initialOwner, projectId: 0, permissionId: 0})`
   - Calls `_emitTransferEvent(address(0), initialOwner, 0)`

**Events**: `OwnershipTransferred(address indexed previousOwner, address indexed newOwner, address caller)` -- emitted as `OwnershipTransferred(address(0), initialOwner, msg.sender)`

**Edge cases**:
- `owner()` returns `jbOwner.owner` directly (no `PROJECTS.ownerOf()` lookup since `projectId == 0`)
- Ownership does NOT follow NFT transfers -- it is static until explicitly transferred via `transferOwnership()` or `transferOwnershipToProject()`
- `PROJECTS` can be `address(0)` in this mode since it is never consulted for ownership resolution. However, `transferOwnershipToProject()` will revert if `PROJECTS` is `address(0)` (the `PROJECTS.count()` call reverts).

---

## Journey 2: Transfer Ownership to a Different Address

**Entry point**: `JBOwnableOverrides.transferOwnership(address newOwner)`

**Who can call**: The current owner (resolved via `PROJECTS.ownerOf()` if project-owned, or `jbOwner.owner` if address-owned), or any address with the configured `permissionId` (or ROOT) via `JBPermissions`.

**Parameters**:
- `newOwner` -- The address to transfer ownership to (must not be `address(0)`)

**State changes**:
1. `_checkOwner()` validates the caller against the resolved owner and `permissionId`
2. Validates `newOwner != address(0)` (reverts with `JBOwnableOverrides_InvalidNewOwner`)
3. `_transferOwnership(newOwner, 0)` executes:
   - Records `oldOwner` (resolved from current `jbOwner`, with try-catch for burned project NFTs)
   - Overwrites `jbOwner = JBOwner({owner: newOwner, projectId: 0, permissionId: 0})`
   - Calls `_emitTransferEvent(oldOwner, newOwner, 0)`

**Events**: `OwnershipTransferred(address indexed previousOwner, address indexed newOwner, address caller)` -- emitted as `OwnershipTransferred(oldOwner, newOwner, msg.sender)`

**Edge cases**:
- If the contract was previously project-owned, `projectId` is now 0 (project ownership is cleared)
- `permissionId` is reset to 0, revoking all previously delegated permissions. The new owner must call `setPermissionId()` to re-enable delegated access.
- The previous owner (or their delegates) can no longer call `onlyOwner` functions
- `newOwner` can immediately call `onlyOwner` functions without any additional setup

---

## Journey 3: Transfer Ownership to a Juicebox Project

**Entry point**: `JBOwnableOverrides.transferOwnershipToProject(uint256 projectId)`

**Who can call**: The current owner (resolved via `PROJECTS.ownerOf()` if project-owned, or `jbOwner.owner` if address-owned), or any address with the configured `permissionId` (or ROOT) via `JBPermissions`.

**Parameters**:
- `projectId` -- The ID of the Juicebox project to transfer ownership to (must be non-zero, fit in `uint88`, and refer to an existing project)

**State changes**:
1. `_checkOwner()` validates the caller
2. Validates `projectId != 0` and `projectId <= type(uint88).max` (reverts with `JBOwnableOverrides_InvalidNewOwner`)
3. Validates `projectId <= PROJECTS.count()` (reverts with `JBOwnableOverrides_ProjectDoesNotExist`)
4. `_transferOwnership(address(0), uint88(projectId))` executes:
   - Records `oldOwner` (resolved from current `jbOwner`)
   - Overwrites `jbOwner = JBOwner({owner: address(0), projectId: uint88(projectId), permissionId: 0})`
   - Calls `_emitTransferEvent(oldOwner, address(0), uint88(projectId))`

**Events**: `OwnershipTransferred(address indexed previousOwner, address indexed newOwner, address caller)` -- emitted as `OwnershipTransferred(oldOwner, PROJECTS.ownerOf(projectId), msg.sender)`

**Edge cases**:
- The project existence check (`projectId <= PROJECTS.count()`) prevents transferring to a nonexistent project
- The `uint88` cast does not truncate (the preceding `type(uint88).max` check ensures this)
- `permissionId` is reset to 0 on transfer. The new project owner must call `setPermissionId()` to configure delegation.
- If the project NFT is subsequently burned (hypothetically), `owner()` returns `address(0)` and the contract is effectively renounced
- Unlike the constructor, `_emitTransferEvent` calls `PROJECTS.ownerOf(newProjectId)` without try-catch -- if the project does not exist, the transaction reverts. This is intentional: the `PROJECTS.count()` check above prevents this path.

---

## Journey 4: Delegate Access via Permission ID

**Entry point**: `JBOwnableOverrides.setPermissionId(uint8 permissionId)`

**Who can call**: The current owner (resolved via `PROJECTS.ownerOf()` if project-owned, or `jbOwner.owner` if address-owned), or any address with the currently configured `permissionId` (or ROOT) via `JBPermissions`.

**Parameters**:
- `permissionId` -- The new permission ID to use for `onlyOwner` access delegation

**State changes**:
1. `_checkOwner()` validates the caller
2. `_setPermissionId(permissionId)` writes `jbOwner.permissionId = permissionId`

**Events**: `PermissionIdChanged(uint8 newId, address caller)` -- emitted as `PermissionIdChanged(permissionId, msg.sender)`

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

**Events**: `OwnershipTransferred(address indexed previousOwner, address indexed newOwner, address caller)` -- emitted as `OwnershipTransferred(oldOwner, address(0), msg.sender)`

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

**Edge cases**:
- There is no way to "revive" ownership after the NFT is burned. However, re-minting an NFT with the same ID (if possible) would restore ownership.
- The `jbOwner` struct is NOT cleared -- it still shows the old `projectId`. Only the resolved owner is `address(0)`.
- This behavior is consistent between `owner()` and `_checkOwner()` (both use the same try-catch pattern)
