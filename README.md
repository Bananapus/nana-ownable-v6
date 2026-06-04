# Juicebox Ownable

`@bananapus/ownable-v6` is an ownership helper for contracts that should be controlled by a Juicebox project instead of a fixed wallet. It keeps the familiar `Ownable` shape while letting ownership follow a project NFT and optional project-scoped delegated permissions.

## Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) — system architecture and component interactions
- [INVARIANTS.md](./INVARIANTS.md) — guarantees enforced by the contracts
- [USER_JOURNEYS.md](./USER_JOURNEYS.md) — typical flows for each actor
- [RISKS.md](./RISKS.md) — known risks and operational caveats
- [ADMINISTRATION.md](./ADMINISTRATION.md) — administrative powers and lifecycle
- [SKILLS.md](./SKILLS.md) — reusable patterns and gotchas for builders
- [STYLE_GUIDE.md](./STYLE_GUIDE.md) — code style conventions
- [AUDIT_INSTRUCTIONS.md](./AUDIT_INSTRUCTIONS.md) — guidance for auditors
- [CHANGELOG.md](./CHANGELOG.md) — release notes
- [references/runtime.md](./references/runtime.md) — owner-resolution, transfer, and delegation behavior by surface
- [references/operations.md](./references/operations.md) — change checklist and common failure modes

## Overview

This package extends the standard ownership model in three ways:

- ownership can point to a Juicebox project ID instead of an address
- `owner()` can resolve dynamically to the current holder of that project NFT
- project-owned contracts can let delegated operators satisfy `onlyOwner` through a configured `JBPermissions` permission ID
- address-owned contracts are direct-owner-only

For contracts that are already meant to be owned by a project, this avoids manual ownership transfers when the project NFT changes hands.

Use this repo when ownership should follow a Juicebox project. Do not use it if plain single-address ownership is enough. Standard `Ownable` is simpler.

If the issue is in project ownership itself, start in `nana-core-v6` and `JBProjects`. This repo matters when another contract wants its admin surface to follow that project ownership.

## Key contracts

| Contract | Role |
| --- | --- |
| `JBOwnable` | Concrete contract to inherit when you want Juicebox-aware ownership with a standard `onlyOwner` interface. |
| `JBOwnableOverrides` | Abstract base that holds owner resolution and delegated-permission logic. |
| `IJBOwnable` | Interface for queries, transfers, permission ID changes, and events. |

## Mental model

This package is a small ownership adapter:

1. resolve who the effective owner is
2. optionally allow a delegated permission to satisfy `onlyOwner` when the contract is project-owned
3. preserve an `Ownable`-like interface for downstream contracts

## Read these files first

1. `src/JBOwnable.sol`
2. `src/JBOwnableOverrides.sol`
3. `src/interfaces/IJBOwnable.sol`

## Integration traps

- ownership may resolve to a project NFT holder instead of a fixed address, so caching `owner()` off-chain can go stale
- `owner()` can resolve to `address(0)` if the referenced project NFT is invalid or unreadable, which effectively renounces the contract
- delegated operator access only applies in project-owned mode and depends on a chosen permission ID, not on a generic admin role
- explicit ownership transfers reset the permission ID, but project NFT transfers do not mutate stored owner data
- a project NFT round trip back to the owner who last set `permissionId` can reactivate that owner's still-granted delegates
- ownership transfer and permission-ID updates are part of the security model, not just convenience helpers

## Where state lives

- effective ownership configuration: `JBOwnableOverrides`
- downstream contract state: the inheriting contract
- project ownership truth: `nana-core-v6` when the owner target is a Juicebox project

## High-signal tests

1. `test/Ownable.t.sol`
2. `test/OwnableAttacks.t.sol`
3. `test/RegressionUnmintedProjectHijack.t.sol`
4. `test/regression/BurnLockProtection.t.sol`
5. `test/regression/PermissionIdNFTTransfer.t.sol`
6. `test/regression/StaleDelegateReactivationOnProjectReturn.t.sol`
7. `test/regression/AddressOwnerPermissionPolicy.t.sol`

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

## Repository layout

```text
src/
  JBOwnable.sol
  JBOwnableOverrides.sol
  interfaces/
  structs/
test/
  core, attack, invariant, mock, and regression coverage
```

## Risks and notes

- if ownership is tied to a project NFT and that NFT becomes unreachable, the contract is effectively locked
- project-owned delegated access depends on a chosen permission ID, so bad permission selection is an operational risk
- address-owned contracts cannot enable delegated owner access
- permission IDs reset on explicit ownership transfers; project NFT transfers leave the ID stored but stale unless the
  resolved owner still matches the owner who set it
- transferring ownership to a project validates that the project exists at transfer time, but later project invalidation can still collapse effective ownership to `address(0)`

## For AI agents

- Do not collapse project-based ownership into ordinary wallet-based ownership in your summary.
- Read the attack and regression tests before making claims about burn-lock or unminted-project edge cases.

If ownership should track a project NFT, reach for this; if a fixed wallet is enough, plain `Ownable` is simpler.
