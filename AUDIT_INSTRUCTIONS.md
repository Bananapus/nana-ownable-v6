# Audit Instructions

This repo provides ownership helpers that can follow Juicebox project NFTs instead of a fixed EOA. It is a small repo with outsized privilege impact.

## Audit objective

Find any path that lets the wrong caller pass owner checks, strands a valid owner, or causes downstream contracts to
reason from stale ownership data.

Suggestions of where to look:

- let unauthorized actors satisfy owner checks
- break ownership updates when a project NFT moves or becomes unreadable
- make delegated permission IDs effective for the wrong owner
- leave dependent repos with stale or permanently wrong ownership views

## Scope

In scope:

- `src/JBOwnable.sol`
- `src/JBOwnableOverrides.sol`
- `src/interfaces/`
- `src/structs/`

## Start here

1. `src/JBOwnable.sol`
2. `src/JBOwnableOverrides.sol`

## Security model

These contracts abstract "owner" as a project-based identity. Downstream repos use them to:

- treat a Juicebox project owner as contract owner
- allow project-scoped delegated operators to satisfy `onlyOwner`
- keep admin power aligned with project NFT ownership instead of a static address

## Roles and privileges

| Role | Powers | How constrained |
|------|--------|-----------------|
| Project NFT owner | Become the effective contract owner | Should update automatically with NFT transfers |
| Delegated operator | Satisfy `onlyOwner` through a configured permission ID | Only works while the resolved owner matches the owner who set that ID |

## Integration assumptions

| Dependency | Assumption | What breaks if wrong |
|------------|------------|----------------------|
| Juicebox project ownership | NFT ownership reflects intended authority | Downstream admin checks drift from reality |

## Critical invariants

1. Owner resolution is correct.  
   For any supported mode, `owner()` and owner checks must resolve to the intended authority and no one else.
2. Unreadable project ownership fails closed.
   If `ownerOf` cannot resolve, owner checks must fail without bubbling brittle upstream errors.
3. Delegated permission lifetime is coherent.
   Explicit ownable transfers must clear `permissionId`; project NFT transfers must ignore stale IDs unless the NFT
   returns to the owner who set them.

## Attack surfaces

- owner resolution after project NFT transfer
- zero-address and unreadable-project states
- delegated permission configuration and `_permissionOwner` gating
- downstream assumptions that cache owner state instead of re-reading it

## Verification

- `npm install`
- `forge build`
- `forge test`
