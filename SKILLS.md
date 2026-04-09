# Juicebox Ownable

## Use This File For

- Use this file when the task involves project-based ownership, delegated `onlyOwner` permissions, or how ownership should follow a Juicebox project NFT instead of a fixed wallet.
- Start here, then open the concrete ownable contract, overrides, or tests depending on whether the question is about resolution, transfer, or delegated access.

## Read This Next

| If you need... | Open this next |
|---|---|
| Repo overview and ownership model | [`README.md`](./README.md), [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| Concrete contract | [`src/JBOwnable.sol`](./src/JBOwnable.sol) |
| Resolution and permission logic | [`src/JBOwnableOverrides.sol`](./src/JBOwnableOverrides.sol), [`src/interfaces/`](./src/interfaces/), [`src/structs/`](./src/structs/) |
| Edge, attack, or invariant coverage | [`test/Ownable.t.sol`](./test/Ownable.t.sol), [`test/OwnableEdgeCases.t.sol`](./test/OwnableEdgeCases.t.sol), [`test/OwnableAttacks.t.sol`](./test/OwnableAttacks.t.sol), [`test/regression/`](./test/regression/) |

## Repo Map

| Area | Where to look |
|---|---|
| Main contracts | [`src/`](./src/) |
| Types | [`src/interfaces/`](./src/interfaces/), [`src/structs/`](./src/structs/) |
| Tests | [`test/`](./test/) |

## Purpose

Ownership adapter for contracts that should follow Juicebox project ownership instead of a fixed address, with optional delegated permission IDs layered on top of the familiar `Ownable` pattern.

## Reference Files

- Open [`references/runtime.md`](./references/runtime.md) when you need owner resolution, transfer semantics, or delegated access behavior.
- Open [`references/operations.md`](./references/operations.md) when you need migration pitfalls, test breadcrumbs, or the common stale assumptions around permission resets.

## Working Rules

- Start in [`src/JBOwnableOverrides.sol`](./src/JBOwnableOverrides.sol) when the question is about who the effective owner is or why `onlyOwner` passed or failed.
- Treat ownership transfer and delegated permission resets as security-sensitive.
- When a bug looks like project ownership itself, confirm whether the real source is upstream in `nana-core-v6` rather than this adapter layer.
