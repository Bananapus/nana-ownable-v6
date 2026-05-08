# Audit Instructions

This repo provides ownership helpers that can follow Juicebox project NFTs instead of a fixed EOA. It is a small repo with outsized privilege impact.

## Audit Objective

There is a billion dollars of well-meaning projects' money in the Juicebox Money Engine, growing exponentially. Your job is to hack it before anyone else. Whoever hacks it first saves/steals the money, and you are obsessed with being this winner, while also being a steward of the protocol and wanting it to keep growing safely.

Suggestions of where to look:

- let unauthorized actors satisfy owner checks
- break ownership updates when a project NFT moves, burns, or locks
- let override logic produce a different owner than the project system intends
- leave dependent repos with stale or permanently wrong ownership views

## Scope

In scope:

- `src/JBOwnable.sol`
- `src/JBOwnableOverrides.sol`
- `src/interfaces/`
- `src/structs/`

## Start Here

1. `src/JBOwnable.sol`
2. `src/JBOwnableOverrides.sol`

## Security Model

These contracts abstract "owner" as a project-based identity. Downstream repos use them to:

- treat a Juicebox project owner as contract owner
- apply per-project override rules
- keep admin power aligned with project NFT ownership instead of a static address

## Roles And Privileges

| Role | Powers | How constrained |
|------|--------|-----------------|
| Project NFT owner | Become the effective contract owner | Should update automatically with NFT transfers |
| Override authority | Set alternative owner resolution where allowed | Must not outrank project ownership unexpectedly |

## Integration Assumptions

| Dependency | Assumption | What breaks if wrong |
|------------|------------|----------------------|
| Juicebox project ownership | NFT ownership reflects intended authority | Downstream admin checks drift from reality |

## Critical Invariants

1. Owner resolution is correct.  
   For any supported mode, `owner()` and owner checks must resolve to the intended authority and no one else.
2. Burn and lock behavior is safe.  
   If project ownership is intentionally burned or locked, the helper must not accidentally reopen control or brick valid admin paths.
3. Override precedence is coherent.  
   Overrides must not silently supersede project ownership in cases the design does not permit.

## Attack Surfaces

- owner resolution after project NFT transfer
- zero-address, burn, and lock states
- override configuration and precedence
- downstream assumptions that cache owner state instead of re-reading it

## Verification

- `npm install`
- `forge build`
- `forge test`
