# Juicebox Ownable Risk Register

This file focuses on the ownership-model risks in `JBOwnable`: dynamic ownership through project NFTs, delegated owner authority, and the mismatch between EOA-style expectations and Juicebox project control.

## How to use this file

- Read `Priority risks` first; most failures here are authority-model misunderstandings rather than arithmetic bugs.
- Use the detailed sections to understand what changes when ownership follows a project instead of a fixed address.
- Treat `Invariants to Verify` as the minimal proof that owner resolution stays coherent.

## Priority risks

| Priority | Risk | Why it matters | Primary controls |
|----------|------|----------------|------------------|
| P1 | Misunderstanding dynamic owner resolution | Ownership can move when the project NFT moves or when permissions change, surprising integrators that expect static `Ownable` semantics. | Clear docs, careful integration review, and explicit tests around ownership transfer paths. |
| P1 | Over-broad delegated owner permissions | `JBPermissions` can broaden who effectively acts as owner; sloppy configuration expands blast radius fast. | Permission hygiene and explicit review of delegated owner grants. |
| P2 | Interoperability assumptions with standard `Ownable` tooling | Some tooling assumes `owner()` maps to one address with no external permission system behind it. | Integration testing with downstream tooling and documentation of semantic differences. |


## 1. Trust Assumptions

- **JBPermissions.** Permission checks delegate to JBPermissions contract. A bug in JBPermissions affects all JBOwnable contracts.
- **JBProjects ERC-721.** When owned by a project, ownership follows the ERC-721 token. Whoever holds the project NFT has owner access.
- **Permission Delegation.** Anyone granted the configured `permissionId` via JBPermissions gets owner-equivalent access for the scoped function.

## 2. Known Risks

- **Project NFT transfer = ownership transfer.** If ownership is tied to a project ID, anyone who acquires the project NFT (via transfer, marketplace purchase, or social engineering) gains full owner access to all contracts using that JBOwnable instance. Project NFT holders must treat the NFT as a high-value key.
- **Dual ownership ambiguity.** Setting both `newOwner` and `projectId` to non-zero reverts, but the two-mode design could confuse integrators about which mode is active. `jbOwner()` exposes both fields for inspection.
- **`renounceOwnership` permanently disables all owner-gated functions.** Defined directly in `JBOwnableOverrides` (not inherited from OpenZeppelin's `Ownable` -- the contract does not inherit from `Ownable`). Once called, `owner()` returns `address(0)` and all `onlyOwner` / `_checkOwner()` calls revert permanently. There is no recovery mechanism. This applies whether ownership is direct (address) or project-based (project NFT holder).

## 3. Accepted Behaviors

- **Permission ID reset on transfer.** `permissionId` resets to 0 on ownership transfer, which temporarily locks out delegated operators. This is intentional -- it prevents permission clashes for new owners.
- **Burned/invalid project NFT.** If the project NFT were burned or `ownerOf` reverted, the contract would be effectively renounced (owner resolves to `address(0)`). Defensive try-catch in `owner()` and `_checkOwner()` handles this gracefully. JBProjects V6 has no burn function, so this scenario cannot occur in practice.
- **`transferOwnershipToProject` rejects non-existent projects.** The function checks `projectId > PROJECTS.count()` and reverts, preventing transfers to non-existent projects.

## 4. Invariants to Verify

- Ownership is always exactly one of: direct address OR project NFT holder (never both, never neither unless renounced).
- `_checkOwner()` reverts for all callers when the owner resolves to `address(0)`.
- `permissionId` is correctly reset to 0 on every ownership transfer.
- After `renounceOwnership()`, `jbOwner()` returns `(address(0), 0, 0)` and no address can pass `_checkOwner()`.
- `transferOwnershipToProject(projectId)` reverts for all `projectId > PROJECTS.count()` at call time.
