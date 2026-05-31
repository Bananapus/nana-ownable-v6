# Architecture

## Purpose

`nana-ownable-v6` adapts `Ownable` to the Juicebox model. A contract can be owned by an address or by a Juicebox project NFT, and project-owned contracts can let delegated operators satisfy `onlyOwner` through `JBPermissions`.

## System Overview

This repo is an ownership primitive, not a policy layer. `JBOwnable` gives downstream repos a familiar inheritance surface. `JBOwnableOverrides` implements dynamic owner resolution, ownership transfer, renounce behavior, direct address-owner checks, and project-scoped delegated permission checks.

Ownership can follow the current holder of a Juicebox project NFT instead of staying fixed to one address.

## Core Invariants

- project-owned contracts must resolve the owner dynamically from the current project NFT holder
- address-owned contracts must only accept the stored owner address
- explicit ownership transfers reset the delegated permission ID
- project NFT transfers do not mutate stored owner data; `_permissionOwner` decides whether a stored permission ID is
  effective
- if the project NFT returns to the owner who last set `permissionId`, that owner's still-granted delegates can become
  effective again
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
  -> if address-owned, accept only the stored owner address
  -> if project-owned, resolve the current project NFT holder
  -> ignore delegated permissions if the resolved project owner differs from _permissionOwner
  -> accept either the resolved project owner or an operator with the effective JB permission
```

## Accounting Model

No treasury accounting lives here. The important state is ownership resolution data and delegated permission ID.

## Security Model

- ownership resolution edge cases matter more than surface API shape
- project-owned permission delegation is simple but security-sensitive because it composes with a global permission registry
- unresolvable project ownership is intentionally fail-closed

## Safe Change Guide

- be conservative with transfer and renounce semantics
- if event emission or transfer behavior changes, inspect deployer wrappers and inheriting repos
- if project-based ownership semantics change, re-check unminted-project and unresolvable-project behavior explicitly
- keep explicit ownership-transfer resets and project-NFT-transfer staleness checks distinct

## Canonical Checks

- baseline address-owner and project-owner behavior:
  `test/Ownable.t.sol`
- transfer, renounce, and hostile-call edge cases:
  `test/OwnableEdgeCases.t.sol`
  `test/OwnableAttacks.t.sol`
- unminted-project and burn-lock safety:
  `test/RegressionUnmintedProjectHijack.t.sol`
  `test/regression/BurnLockProtection.t.sol`
- permission staleness and reactivation:
  `test/regression/PermissionIdNFTTransfer.t.sol`
  `test/regression/StaleDelegateReactivationOnProjectReturn.t.sol`
- address-owned direct-owner policy:
  `test/regression/AddressOwnerPermissionPolicy.t.sol`
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
- `test/RegressionUnmintedProjectHijack.t.sol`
- `test/regression/BurnLockProtection.t.sol`
- `test/regression/PermissionIdNFTTransfer.t.sol`
- `test/regression/RootPermissionBypassesPermissionIdZero.t.sol`
- `test/regression/StaleDelegateReactivationOnProjectReturn.t.sol`
- `test/regression/AddressOwnerPermissionPolicy.t.sol`
- `test/OwnableInvariantTests.sol`
- `references/runtime.md`
- `references/operations.md`
