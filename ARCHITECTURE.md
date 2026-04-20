# Architecture

## Purpose

`nana-ownable-v6` adapts `Ownable` to the Juicebox model. A contract can be owned by an address or by a Juicebox project NFT, and delegated operators can satisfy `onlyOwner` through `JBPermissions`.

## System Overview

The repo is an ownership primitive, not a policy layer. `JBOwnable` exposes a familiar inheritance surface. `JBOwnableOverrides` implements dynamic owner resolution, ownership transfer, renounce behavior, and delegated permission checks. Ownership can follow the current holder of a Juicebox project NFT instead of being fixed to an address.

## Core Invariants

- Project-owned contracts must resolve the owner dynamically from the current project NFT holder.
- The delegated permission ID resets on ownership transfer.
- Pointing ownership at an unminted project can temporarily lock the contract until that project exists.
- A burned or otherwise unresolvable project NFT effectively renounces ownership.
- This repo should stay a drop-in primitive, not grow product-specific access rules.

## Modules

| Module | Responsibility | Notes |
| --- | --- | --- |
| `JBOwnable` | Familiar `onlyOwner` inheritance target | Concrete surface |
| `JBOwnableOverrides` | Resolution, transfer, renounce, and delegated-permission logic | Core behavior |
| `JBOwner` | Packed owner state | Shared struct |
| `IJBOwnable` | Public interface and events | Integration surface |

## Trust Boundaries

- Ownership resolution depends on `JBProjects` and `JBPermissions` from `nana-core-v6`.
- This repo does not create a new permission namespace.
- Contracts that inherit from it may still add policy on top, but the resolution semantics here are infrastructure-level.

## Critical Flows

### Owner Check

```text
onlyOwner modifier
  -> load packed owner state
  -> if project-owned, resolve the current project NFT holder
  -> otherwise use the stored owner address
  -> accept either the resolved owner or an operator with the configured JB permission
```

## Accounting Model

No treasury accounting lives here. The critical state is ownership resolution data and delegated permission ID.

## Security Model

- Ownership resolution edge cases are more important than surface API shape.
- Permission delegation is simple conceptually but security-sensitive because it composes with a global permission registry.
- Unresolvable project ownership is intentionally fail-closed. If `PROJECTS.ownerOf()` cannot resolve, `onlyOwner` should stop working rather than inventing fallback authority.

## Safe Change Guide

- Be conservative with transfer and renounce semantics.
- If event emission or transfer behavior changes, inspect deployer wrappers and inheriting repos.
- If project-based ownership semantics change, re-check unminted-project and unresolvable-project behavior explicitly.
- Do not make delegated permission IDs sticky across ownership transfers.

## Canonical Checks

- baseline address-owner and project-owner behavior:
  `test/Ownable.t.sol`
- transfer, renounce, and hostile-call edge cases:
  `test/OwnableEdgeCases.t.sol`
  `test/OwnableAttacks.t.sol`
- unminted-project and burn-lock safety:
  `test/CodexUnmintedProjectHijack.t.sol`
  `test/regression/BurnLockProtection.t.sol`
- ownership-state invariants:
  `test/OwnableInvariantTests.sol`

## Source Map

- `src/JBOwnable.sol`
- `src/JBOwnableOverrides.sol`
- `src/structs/JBOwner.sol`
- `src/interfaces/IJBOwnable.sol`
- `test/Ownable.t.sol`
- `test/OwnableEdgeCases.t.sol`
- `test/OwnableAttacks.t.sol`
- `test/CodexUnmintedProjectHijack.t.sol`
- `test/regression/BurnLockProtection.t.sol`
- `test/regression/ZeroAddressValidation.t.sol`
- `test/OwnableInvariantTests.sol`
- `references/runtime.md`
- `references/operations.md`
