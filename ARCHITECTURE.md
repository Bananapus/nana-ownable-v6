# Architecture

## Purpose

`nana-ownable-v6` adapts `Ownable` to the Juicebox model. A contract can be owned by an address or by a Juicebox project NFT, and delegated operators can satisfy `onlyOwner` via `JBPermissions`.

## Boundaries

- The repo only solves ownership resolution and owner delegation.
- It does not create a new permission system; it reuses `JBPermissions`.
- It should remain a drop-in ownership primitive, not a product-specific policy layer.

## Main Components

| Component | Responsibility |
| --- | --- |
| `JBOwnable` | Concrete inheritance target with the standard `onlyOwner` surface |
| `JBOwnableOverrides` | Core ownership resolution, transfer, renounce, and permission-ID logic |
| `JBOwner` | Packed owner state: address owner, project owner, and delegated permission ID |
| `IJBOwnable` | Public interface and events |

## Runtime Model

```text
onlyOwner check
  -> read packed owner state
  -> if project-owned, resolve the current project NFT holder
  -> otherwise use the stored owner address
  -> allow the resolved owner or an operator with the configured JB permission
```

## Critical Invariants

- Ownership must resolve dynamically when tied to a project NFT.
- The delegated permission ID resets on ownership transfer so an old operator set does not silently carry over.
- A burned or otherwise unresolvable project NFT effectively renounces ownership for contracts tied to that project.

## Where Complexity Lives

- Most of the subtlety is in ownership resolution edge cases, not in the surface API.
- Permission delegation is simple conceptually but security-sensitive in practice because it composes with a global permission registry.

## Dependencies

- `nana-core-v6` `JBProjects` and `JBPermissions`
- OpenZeppelin `Context` compatibility for normal and meta-transaction-aware usage

## Safe Change Guide

- Be conservative with ownership semantics; many repos treat this as infrastructure.
- If you change event emission or transfer behavior, consider deploy-time wrappers and contracts that override emission.
- Permission-ID behavior is security-sensitive. Do not turn it into a convenience cache with surprising persistence.
