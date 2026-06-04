# Ownable Operations

## Change checklist

- If you edit owner resolution, verify both direct ownership and project-owned cases.
- If you edit permission handling, verify explicit transfer resets, project NFT transfer staleness, and NFT round-trip
  reactivation.
- If an integration expects long-lived delegated access, confirm whether explicit transfers clear it or project NFT
  transfers merely make it stale.
- If the change touches project ownership, check unminted-project and burn-lock regressions before assuming the happy-path tests are enough.

## Common failure modes

- Integrations assume delegated operators survive ownership transfer.
- Bugs are blamed on this repo when the underlying project NFT ownership changed upstream.
- A project-owned contract is treated like an address-owned contract and the wrong actor is allowed through `onlyOwner`.
- Operators are assumed inactive after a project NFT round trip even though the prior owner's grants can reactivate.
