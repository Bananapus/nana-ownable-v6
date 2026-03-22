# RISKS.md -- nana-ownable-v6

## 1. Trust Assumptions

- **JBPermissions.** Permission checks delegate to JBPermissions contract. A bug in JBPermissions affects all JBOwnable contracts.
- **JBProjects ERC-721.** When owned by a project, ownership follows the ERC-721 token. Whoever holds the project NFT has owner access.
- **Permission Delegation.** Anyone granted the configured `permissionId` via JBPermissions gets owner-equivalent access for the scoped function.

## 2. Known Risks

- **Project NFT transfer = ownership transfer.** If ownership is tied to a project ID, anyone who acquires the project NFT (via transfer, marketplace purchase, or social engineering) gains full owner access to all contracts using that JBOwnable instance. Project NFT holders must treat the NFT as a high-value key.
- **Permission ID reset on transfer.** `permissionId` resets to 0 on ownership transfer, which could temporarily lock out delegated operators. By design -- prevents permission clashes for new owners.
- **Burned/invalid project NFT.** If the project NFT is burned or `ownerOf` reverts, the contract is effectively renounced (owner resolves to `address(0)`). Defensive try-catch in `owner()` and `_checkOwner()`. JBProjects V6 has no burn function, so this is a defensive measure.
- **Dual ownership ambiguity.** Setting both `newOwner` and `projectId` to non-zero reverts, but the two-mode design could confuse integrators about which mode is active. `jbOwner()` exposes both fields for inspection.
- **`transferOwnershipToProject` with future project.** Checks `projectId > PROJECTS.count()` to prevent transferring to non-existent projects.
- **`renounceOwnership` permanently disables all owner-gated functions.** Inherited from OpenZeppelin's `Ownable`. Once called, `owner()` returns `address(0)` and all `onlyOwner` / `_checkOwner()` calls revert permanently. There is no recovery mechanism. This applies whether ownership is direct (address) or project-based (project NFT holder).
- **`transferOwnershipToProject` boundary condition.** The function checks `projectId > PROJECTS.count()` to prevent transferring to non-existent projects. At the exact boundary (`projectId == PROJECTS.count()`), the transfer succeeds because that project ID exists. If called in the same transaction as a `PROJECTS.createFor()`, the ordering matters — the project must be created before the ownership transfer.

## 3. Invariants to Verify

- Ownership is always exactly one of: direct address OR project NFT holder (never both, never neither unless renounced).
- `_checkOwner()` reverts for all callers when the owner resolves to `address(0)`.
- `permissionId` is correctly reset to 0 on every ownership transfer.
- After `renounceOwnership()`, `jbOwner()` returns `(address(0), 0, 0)` and no address can pass `_checkOwner()`.
- `transferOwnershipToProject(projectId)` reverts for all `projectId > PROJECTS.count()` at call time.
