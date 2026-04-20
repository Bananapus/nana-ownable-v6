# Architecture

## Purpose

`nana-ownable-v6` adapts `Ownable` to the Juicebox model. A contract can be owned by an address or by a Juicebox project NFT, and delegated operators can satisfy `onlyOwner` through `JBPermissions`.

## System Overview

This repo is an ownership primitive, not a policy layer. `JBOwnable` gives downstream repos a familiar inheritance surface. `JBOwnableOverrides` implements dynamic owner resolution, ownership transfer, renounce behavior, and delegated permission checks.

Ownership can follow the current holder of a Juicebox project NFT instead of staying fixed to one address.

## Core Invariants

- project-owned contracts must resolve the owner dynamically from the current project NFT holder
- the delegated permission ID resets on ownership transfer
- pointing ownership at an unminted project can temporarily lock the contract until that project exists
- an invalid or otherwise unresolvable project NFT effectively renounces ownership
- this repo should stay a drop-in primitive, not grow product-specific access rules

## Modules

| Module | Responsibility | Notes |
| --- | --- | --- |
| `JBOwnable` | Familiar `onlyOwner` inheritance target | Concrete surface |
| `JBOwnableOverrides` | Resolution, transfer, renounce, and delegated-permission logic | Core behavior |
| `JBOwner` | Packed owner state | Shared struct |
| `IJBOwnable` | Public interface and events | Integration surface |

## Trust Boundaries

- ownership resolution depends on `JBProjects` and `JBPermissions` from `nana-core-v6`
- this repo does not create a new permission namespace
- inheriting contracts may add policy on top, but the resolution semantics here are infrastructure-level

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

No treasury accounting lives here. The important state is ownership resolution data and delegated permission ID.

## Security Model

- ownership resolution edge cases matter more than surface API shape
- permission delegation is simple but security-sensitive because it composes with a global permission registry
- unresolvable project ownership is intentionally fail-closed

## Safe Change Guide

- be conservative with transfer and renounce semantics
- if event emission or transfer behavior changes, inspect deployer wrappers and inheriting repos
- if project-based ownership semantics change, re-check unminted-project and unresolvable-project behavior explicitly
- do not make delegated permission IDs sticky across ownership transfers

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
