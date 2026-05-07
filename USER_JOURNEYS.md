# User Journeys

## Repo Purpose

This repo adapts `Ownable`-style control to Juicebox project ownership and project-scoped operator permissions. It is an ownership adapter. It does not replace the underlying ownership or permission registries in [nana-core-v6](../nana-core-v6/USER_JOURNEYS.md).

## Primary Actors

- protocol or product teams that want `onlyOwner` to follow a project NFT
- operators who need owner-like access without receiving the project itself
- auditors checking whether delegated owner semantics strand or over-grant authority

## Key Surfaces

- `JBOwnable`: `Ownable`-style adapter whose owner follows a Juicebox project
- `JBOwnableOverrides`: extension that lets a project-scoped permission satisfy `onlyOwner`
- `owner()`, `transferOwnership(...)`, `transferOwnershipToProject(...)`, `setPermissionId(...)`: core ownership-resolution and migration paths

## Journey 1: Give A Contract To A Juicebox Project Instead Of A Wallet

**Actor:** downstream contract author.

**Intent:** make a contract follow Juicebox project ownership instead of a fixed EOA or multisig.

**Preconditions**
- the downstream contract wants `onlyOwner` ergonomics
- a project ID and `JBProjects` dependency are already known

**Main Flow**
1. Inherit `JBOwnable` or `JBOwnableOverrides`.
2. Initialize ownership with the relevant project ID and `JBProjects` reference.
3. Let `owner()` resolve through the current project NFT holder instead of a fixed address.

**Failure Modes**
- the contract assumes ordinary `Ownable` transfer semantics after adopting project-based ownership
- the wrong project ID is configured
- reviewers ignore the adapter and audit the downstream contract as if `owner` were fixed

**Postconditions**
- `owner()` now resolves through the configured project NFT instead of a fixed wallet

## Journey 2: Delegate Owner-Level Access To Operators

**Actor:** current project owner.

**Intent:** let an operator satisfy `onlyOwner` for one contract without transferring the project.

**Preconditions**
- the downstream contract uses `JBOwnableOverrides`
- the team has chosen the permission ID that should count as delegated owner access

**Main Flow**
1. Choose the permission ID the downstream contract should respect.
2. Grant that permission through `JBPermissions`.
3. `JBOwnableOverrides` treats the operator as satisfying `onlyOwner` for that contract.

**Failure Modes**
- teams grant a broader permission than intended
- downstream reviewers forget that `onlyOwner` may resolve through permissions instead of direct ownership
- operators keep stale permissions after governance changes

**Postconditions**
- the chosen operator can satisfy `onlyOwner` without receiving direct ownership of the project or contract

## Journey 3: Change The Delegated Permission ID Without Changing Ownership

**Actor:** current effective owner.

**Intent:** rotate delegated owner policy without changing the underlying owner.

**Preconditions**
- the contract already uses `JBOwnableOverrides`
- all operators who need continued access can be regranted under the new permission ID

**Main Flow**
1. Update the permission ID the adapter treats as owner-equivalent with `setPermissionId(...)`.
2. Re-grant the new permission where needed.
3. Re-audit operator assumptions because the old permission no longer satisfies `onlyOwner`.

**Failure Modes**
- operator access disappears unintentionally after a permission-ID rotation
- teams forget that old delegations stop working immediately

**Postconditions**
- the adapter now resolves delegated owner access through the new permission ID only

## Journey 4: Transfer Or Burn Ownership Deliberately

**Actor:** current effective owner.

**Intent:** move or remove control with full awareness of the consequences.

**Preconditions**
- the team understands whether admin recovery should remain possible
- downstream integrations can tolerate the new owner model

**Main Flow**
1. Use `transferOwnership(...)` for an address owner or `transferOwnershipToProject(...)` for a project owner.
2. Re-establish delegated permission policy if the new owner still wants operators.
3. Renounce only when permanent admin loss is intentional.

**Failure Modes**
- ownership is burned even though the downstream contract still needs administration
- teams forget that delegated permissions reset across ownership changes

**Postconditions**
- control moves to the chosen address or project, or is intentionally removed

## Trust Boundaries

- this repo trusts `JBProjects` for project ownership and `JBPermissions` for delegated authority
- downstream contracts still need their own audit because this adapter changes who satisfies `onlyOwner`

## Hand-Offs

- Use [nana-core-v6](../nana-core-v6/USER_JOURNEYS.md) for the project-NFT and permission machinery this adapter depends on.
- Use [nana-permission-ids-v6](../nana-permission-ids-v6/USER_JOURNEYS.md) if you need the shared numeric permission vocabulary for delegated `onlyOwner` checks.
