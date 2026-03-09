# nana-ownable-v6 — Risks

## Trust Assumptions

1. **JBPermissions** — Permission checks delegate to JBPermissions contract. A bug in JBPermissions affects all JBOwnable contracts.
2. **JBProjects ERC-721** — When owned by a project, ownership follows the ERC-721 token. Whoever holds the project NFT has owner access.
3. **Permission Delegation** — Anyone granted the configured `permissionId` via JBPermissions gets owner-equivalent access.

## Known Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| Permission escalation | Granting `permissionId` gives full owner access to that function | Only grant to trusted operators |
| Project NFT transfer | Transferring the project NFT transfers ownership of all JBOwnable contracts tied to it | Intentional design; use multisig for project NFT |
| Renounce is permanent | `renounceOwnership()` is irreversible | Standard OpenZeppelin pattern |
| Zero address project | Setting `projectId = 0` with `owner = address(0)` permanently locks ownership | Validate before calling |

## Privileged Roles

| Role | Access | Scope |
|------|--------|-------|
| Owner (address or project holder) | All `onlyOwner` functions | Per-contract |
| Permission delegates | `onlyOwner` functions via JBPermissions | Per-contract, per-permissionId |
