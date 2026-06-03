# Juicebox Ownable Risk Register

This file covers the ownership-model risks in `JBOwnable`: dynamic ownership through project NFTs, project-scoped delegated owner authority, address-owned direct-owner checks, and mismatches with standard `Ownable` expectations.

## How to use this file

- Read `Priority risks` first. Most failures here come from authority-model mistakes, not arithmetic bugs.
- Use the later sections to understand what changes when ownership follows a project instead of a fixed address.
- Treat `Invariants to verify` as the minimum proof that owner resolution stays coherent.

## Priority risks

| Priority | Risk | Why it matters | Primary controls |
|----------|------|----------------|------------------|
| P1 | Misunderstanding dynamic owner resolution | Ownership can move when the project NFT moves or when project-owned permissions change, which breaks static `Ownable` assumptions. | Clear docs, careful integration review, and explicit tests around transfer paths. |
| P1 | Over-broad or stale project-owned delegated permissions | `JBPermissions` can broaden who effectively acts as owner for project-owned contracts, and project NFT round trips can reactivate old grants. | Permission hygiene, explicit review of delegated grants, and revocation after ownership changes. |
| P2 | Tooling assumptions about standard `Ownable` | Some tooling assumes `owner()` maps to one address with no external permission system behind it. | Integration testing and clear documentation of the semantic differences. |

## 1. Trust assumptions

- **`JBPermissions` works correctly.** A bug there affects every project-owned `JBOwnable` contract that relies on delegated owner access.
- **`JBProjects` ownership is the source of truth.** When a contract is project-owned, whoever holds the project NFT has owner access.
- **Delegated permission means owner-equivalent access for project-owned contracts.** Anyone granted the effective `permissionId` through `JBPermissions` can satisfy owner checks for the scoped project-owned contract.
- **Deployment inputs are intentional.** Constructor dependencies such as `JBProjects` and `JBPermissions` are assumed to be valid, and if `initialProjectIdOwner != 0`, deployers must understand whether that project already exists.

## 2. Known risks

- **Project NFT transfer changes contract ownership.** Anyone who acquires the project NFT gains owner access to contracts using that project-owned mode.
- **Two ownership modes can confuse integrations.** Setting both `newOwner` and `projectId` is disallowed, but integrators still need to check which mode is active.
- **`renounceOwnership` is final.** Once called, `owner()` resolves to `address(0)` and owner-gated functions stop working permanently unless a downstream contract adds its own recovery path.
- **Constructor pre-binding can intentionally lock the contract.** If a deployer points ownership at a future project ID, `owner()` resolves to `address(0)` until that project exists.
- **Project NFT transfers do not clear stored permission IDs.** `_permissionOwner` makes those IDs ineffective while a different owner holds the NFT, but storage still records the old ID.
- **Address-owned contracts are direct-owner-only.** They do not route through `JBPermissions`, even if the stored owner has wildcard project permissions configured.
- **`PROJECTS == address(0)` breaks project-owned mode.** This is a deployment-layer invariant, not a runtime-supported configuration.
- **Unminted project ID ownership.** Contracts using `JBOwnableOverrides` can be configured with an `initialProjectIdOwner` that references a project ID not yet minted. The first account to mint that sequential project ID will become the effective owner of the contract. Deployers must ensure the referenced project ID is already minted, or deploy the ownable contract and the project in the same transaction to prevent front-running.

## 3. Accepted behaviors

- **Permission ID resets on explicit transfer.** `permissionId` resets to `0` on `transferOwnership`, `transferOwnershipToProject`, and `renounceOwnership` so old delegated operators do not automatically retain power. Project NFT transfers are different — see the round-trip reactivation entry below.
- **`permissionId = 0` means direct-owner-only mode.** This is a valid configuration, not an error state.
- **Address-owned contracts cannot enable delegation.** `setPermissionId(nonzero)` reverts while `projectId == 0`; project ownership is required before nonzero permission IDs can grant owner access.
- **Invalid project ownership resolves fail-closed.** If `ownerOf` cannot resolve, the contract is effectively renounced until ownership becomes readable again.
- **`transferOwnershipToProject` rejects non-existent projects.** The function checks existence at transfer time.
- **Constructor pre-binding to a future project ID is supported.** This is useful in controlled deployment flows, but dangerous if the deployer does not control mint sequencing.
- **Transfer events can temporarily show `address(0)`.** When ownership points to an unminted future project, the transfer event shows `address(0)` until ownership can resolve dynamically.
- **NFT round-trip reactivates stale delegate permissions.** When a project NFT round-trips back to the original owner, `_checkOwner`'s comparison `resolvedOwner == _permissionOwner` becomes true again, reactivating whatever `permissionId` and `JBPermissions` operator grants were configured before the transfer. This is accepted by design: the owner is responsible for revoking stale permissions after reclaiming the NFT. The permission system intentionally defers to `JBPermissions` for operator management rather than tracking ownership epochs.

## 4. Invariants to verify

- ownership is always exactly one of: direct address or project NFT holder
- `_checkOwner()` reverts for all callers when the owner resolves to `address(0)`
- `permissionId` resets to `0` on explicit ownership-transfer and renounce paths
- address-owned contracts bypass `JBPermissions`, and `setPermissionId(nonzero)` reverts while `projectId == 0`
- project NFT transfer preserves stored `permissionId` but makes it ineffective while the resolved owner differs from
  `_permissionOwner`
- after `renounceOwnership()`, `jbOwner()` returns `(address(0), 0, 0)` and no address can pass `_checkOwner()`
- `transferOwnershipToProject(projectId)` reverts for all `projectId > PROJECTS.count()` at call time
