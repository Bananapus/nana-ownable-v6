# Juicebox Ownable

`@bananapus/ownable-v6` is an ownership helper for contracts that should be controlled by a Juicebox project rather than a fixed wallet. It keeps the familiar `Ownable` shape while letting ownership follow a project NFT and optional delegated permissions.

Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)

## Overview

This package extends the standard ownership model in three useful ways:

- ownership can point to a Juicebox project ID instead of an address
- `owner()` resolves dynamically to the current holder of that project NFT
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
