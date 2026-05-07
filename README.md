# Juicebox Ownable

`@bananapus/ownable-v6` is an ownership helper for contracts that should be controlled by a Juicebox project instead of a fixed wallet. It keeps the familiar `Ownable` shape while letting ownership follow a project NFT and optional delegated permissions.

Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)  
User journeys: [USER_JOURNEYS.md](./USER_JOURNEYS.md)  
Skills: [SKILLS.md](./SKILLS.md)  
Risks: [RISKS.md](./RISKS.md)  
Administration: [ADMINISTRATION.md](./ADMINISTRATION.md)  
Review instructions: [REVIEW_GUIDE.md](./REVIEW_GUIDE.md)

## Overview

This package extends the standard ownership model in three ways:

- ownership can point to a Juicebox project ID instead of an address
- `owner()` can resolve dynamically to the current holder of that project NFT
- delegated operators can satisfy `onlyOwner` through a configured `JBPermissions` permission ID

For contracts that are already meant to be owned by a project, this avoids manual ownership transfers when the project NFT changes hands.

Use this repo when ownership should follow a Juicebox project. Do not use it if plain single-address ownership is enough. Standard `Ownable` is simpler.

If the issue is in project ownership itself, start in `nana-core-v6` and `JBProjects`. This repo matters when another contract wants its admin surface to follow that project ownership.

## Key Contracts

| Contract | Role |
| --- | --- |
| `JBOwnable` | Concrete contract to inherit when you want Juicebox-aware ownership with a standard `onlyOwner` interface. |
| `JBOwnableOverrides` | Abstract base that holds owner resolution and delegated-permission logic. |
| `IJBOwnable` | Interface for queries, transfers, permission ID changes, and events. |

## Mental Model

This package is a small ownership adapter:

1. resolve who the effective owner is
2. optionally allow a delegated permission to satisfy `onlyOwner`
3. preserve an `Ownable`-like interface for downstream contracts

## Read These Files First

1. `src/JBOwnable.sol`
2. `src/JBOwnableOverrides.sol`
3. `src/interfaces/IJBOwnable.sol`

## Integration Traps

- ownership may resolve to a project NFT holder instead of a fixed address, so caching `owner()` off-chain can go stale
- `owner()` can resolve to `address(0)` if the referenced project NFT is invalid or unreadable, which effectively renounces the contract
- delegated operator access depends on a chosen permission ID, not on a generic admin role
- ownership transfer and permission-ID updates are part of the security model, not just convenience helpers

## Where State Lives

- effective ownership configuration: `JBOwnableOverrides`
- downstream contract state: the inheriting contract
- project ownership truth: `nana-core-v6` when the owner target is a Juicebox project

## High-Signal Tests

1. `test/Ownable.t.sol`
2. `test/OwnableAttacks.t.sol`
3. `test/RegressionUnmintedProjectHijack.t.sol`
4. `test/regression/BurnLockProtection.t.sol`

## Install

```bash
npm install @bananapus/ownable-v6
```

## Development

```bash
npm install
forge build
forge test
```

## Repository Layout

```text
src/
  JBOwnable.sol
  JBOwnableOverrides.sol
  interfaces/
  structs/
test/
  core, attack, invariant, mock, and regression coverage
```

## Risks And Notes

- if ownership is tied to a project NFT and that NFT becomes unreachable, the contract is effectively locked
- delegated access depends on a chosen permission ID, so bad permission selection is an operational risk
- permission IDs reset on ownership transfer, which is safer by default but easy to miss
- transferring ownership to a project validates that the project exists at transfer time, but later project invalidation can still collapse effective ownership to `address(0)`

## For AI Agents

- Do not collapse project-based ownership into ordinary wallet-based ownership in your summary.
- Read the attack and regression tests before making claims about burn-lock or unminted-project edge cases.
