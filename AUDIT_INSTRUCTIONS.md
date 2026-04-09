# Audit Instructions

This repo provides ownership helpers that can follow Juicebox project NFTs instead of a fixed EOA. It is a small repo with disproportionate privilege impact.

## Objective

Find issues that:
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

## System Model

These contracts abstract “owner” as a project-based identity. Downstream repos use them to:
- treat a Juicebox project owner as contract owner
- apply per-project override rules
- keep admin power aligned with project NFT ownership instead of a static address

## Critical Invariants

1. Owner resolution is correct
For any supported mode, `owner()` or equivalent checks must resolve to the intended authority and no one else.

2. Burn and lock behavior is safe
If project ownership is intentionally burned or locked, the helper must not accidentally reopen control or brick valid admin paths.

3. Override precedence is coherent
Overrides must not silently supersede project ownership in cases the design does not permit.

## Threat Model

Prioritize:
- zero-address handling
- NFT transfer edge cases
- irreversible lock or burn flows
- meta-transaction context if used by downstream callers

## Build And Verification

Standard workflow:
- `npm install`
- `forge build`
- `forge test`

Good findings in this repo show privilege drift in dependent systems, not just a local discrepancy in a view function.
