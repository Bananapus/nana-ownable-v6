# Juicebox Ownable

## Use This File For

- Use this file when the task involves project-based ownership, delegated `onlyOwner` permissions, or ownership that should follow a Juicebox project NFT instead of a fixed wallet.
- Start here, then decide whether the question is about owner resolution, permission delegation, or ownership transfer semantics.

## Read This Next

| If you need... | Open this next |
|---|---|
| Repo overview and ownership model | [`README.md`](./README.md), [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| Concrete contract | [`src/JBOwnable.sol`](./src/JBOwnable.sol) |
| Resolution and permission logic | [`src/JBOwnableOverrides.sol`](./src/JBOwnableOverrides.sol), [`src/interfaces/`](./src/interfaces/), [`src/structs/`](./src/structs/) |
| Runtime and migration assumptions | [`references/runtime.md`](./references/runtime.md), [`references/operations.md`](./references/operations.md) |
| Edge, attack, and invariant coverage | [`test/Ownable.t.sol`](./test/Ownable.t.sol), [`test/OwnableEdgeCases.t.sol`](./test/OwnableEdgeCases.t.sol), [`test/OwnableAttacks.t.sol`](./test/OwnableAttacks.t.sol), [`test/OwnableInvariantTests.sol`](./test/OwnableInvariantTests.sol), [`test/CodexUnmintedProjectHijack.t.sol`](./test/CodexUnmintedProjectHijack.t.sol) |

## Repo Map

| Area | Where to look |
|---|---|
| Main contracts | [`src/`](./src/) |
| Types | [`src/interfaces/`](./src/interfaces/), [`src/structs/`](./src/structs/) |
| Tests | [`test/`](./test/) |

## Purpose

Ownership adapter for contracts that should follow Juicebox project ownership instead of a fixed address, with optional delegated permission IDs on top of the familiar `Ownable` pattern.

## Reference Files

- Open [`references/runtime.md`](./references/runtime.md) when you need owner resolution, transfer semantics, or delegated access behavior.
- Open [`references/operations.md`](./references/operations.md) when you need migration pitfalls, test breadcrumbs, or the common stale assumptions around permission resets.

## Working Rules

- Start in [`src/JBOwnableOverrides.sol`](./src/JBOwnableOverrides.sol) when the question is about who the effective owner is or why `onlyOwner` passed or failed.
- Treat ownership transfer and delegated permission resets as security-sensitive.
- Project-based ownership can intentionally become unusable if it points at an unminted or invalid project.
- Unminted or unexpectedly transferred project NFTs can change the effective owner surface. Check the project lifecycle, not just this adapter.
- When a bug looks like project ownership itself, confirm whether the real source is upstream in `nana-core-v6` rather than this adapter.
