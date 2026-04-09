# Ownable Operations

## Change Checklist

- If you edit owner resolution, verify both direct ownership and project-owned cases.
- If you edit permission handling, verify transfer-time reset behavior.
- If an integration expects long-lived delegated access, confirm whether the transfer-reset rule invalidates that assumption.

## Common Failure Modes

- Integrations assume delegated operators survive ownership transfer.
- Bugs are blamed on this repo when the underlying project NFT ownership changed upstream.
