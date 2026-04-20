# Juicebox Ownable

`@bananapus/ownable-v6` is an ownership helper for contracts that should be controlled by a Juicebox project rather than a fixed wallet. It keeps the familiar `Ownable` shape while letting ownership follow a project NFT and optional delegated permissions.

Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)  
User journeys: [USER_JOURNEYS.md](./USER_JOURNEYS.md)  
Skills: [SKILLS.md](./SKILLS.md)  
Risks: [RISKS.md](./RISKS.md)  
Administration: [ADMINISTRATION.md](./ADMINISTRATION.md)  
Audit instructions: [AUDIT_INSTRUCTIONS.md](./AUDIT_INSTRUCTIONS.md)

## Overview

This package extends the standard ownership model in three useful ways:

- ownership can point to a Juicebox project ID instead of an address
- `owner()` resolves dynamically to the current holder of that project NFT when the referenced project remains readable
- delegated operators can satisfy `onlyOwner` through a configurable `JBPermissions` permission ID

For contracts that are already conceptually "owned by the project," this avoids manual ownership transfers when the project NFT changes hands.

Use this repo when ownership should follow a Juicebox project. Do not use it if plain single-address ownership is good enough; standard `Ownable` is simpler.

If your issue is in project ownership itself, start in `nana-core-v6` and `JBProjects`. This repo starts mattering when another contract wants its own admin surface to follow that project ownership.

## Key Contracts

| Contract | Role |
| --- | --- |
| `JBOwnable` | Concrete contract to inherit when you want Juicebox-aware ownership with the standard `onlyOwner` interface. |
| `JBOwnableOverrides` | Abstract base that holds the owner-resolution and permission-checking logic. |
| `IJBOwnable` | Interface for queries, transfers, permission ID changes, and events. |

## Mental Model

This package is a thin ownership adapter:

1. resolve who the effective owner is
2. optionally delegate `onlyOwner` through a permission ID
3. preserve an `Ownable`-like interface for downstream contracts

## Read These Files First

1. `src/JBOwnable.sol`
2. `src/JBOwnableOverrides.sol`
3. `src/interfaces/IJBOwnable.sol`

## Integration Traps

- ownership may resolve to a project NFT holder rather than a fixed address, so caching `owner()` off-chain can become stale
- `owner()` can resolve to `address(0)` if the referenced project NFT is burned, invalid, or otherwise unreadable, which effectively renounces the contract
- delegated operator access depends on a chosen permission ID, not on a generic admin role
- ownership transfer and permission-ID updates are part of the security model, not just convenience helpers

## Where State Lives

- effective ownership configuration lives in `JBOwnableOverrides`
- downstream contract state still lives in the inheriting contract, not in this package
- project ownership truth lives in `nana-core-v6` when the owner target is a Juicebox project

## High-Signal Tests

1. `test/Ownable.t.sol`
2. `test/OwnableAttacks.t.sol`
3. `test/CodexUnmintedProjectHijack.t.sol`
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
- delegated access depends on a chosen permission ID, so collisions with other permission schemes are an operational risk
- permission IDs reset on ownership transfer, which is safer by default but easy to miss if an integration expects long-lived operator access
- transferring ownership to a project validates that the project exists, but later project-NFT invalidation can still collapse effective ownership to `address(0)`

## For AI Agents

- Do not collapse project-based ownership into ordinary wallet-based ownership in your summary.
- Read the attack and regression tests before making claims about burn-lock or unminted-project edge cases.
