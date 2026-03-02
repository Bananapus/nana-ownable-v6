# nana-ownable-v5

Juicebox-aware ownership model that ties contract ownership to a Juicebox project NFT or an address, with delegated access through `JBPermissions`.

## Architecture

| Contract | Description |
|----------|-------------|
| `JBOwnable` | Concrete implementation providing an `onlyOwner` modifier and ownership transfer events. Inherits `JBOwnableOverrides`. |
| `JBOwnableOverrides` | Abstract base containing all ownership logic: owner resolution, transfers, renunciation, and permission delegation via `JBPermissions`. |

### Supporting Types

| Type | Description |
|------|-------------|
| `JBOwner` | Struct packing `address owner`, `uint88 projectId`, and `uint8 permissionId` into a single slot. |
| `IJBOwnable` | Interface exposing ownership queries, transfers, renunciation, and permission ID management. |

### Ownership Modes

1. **Project ownership** -- If `JBOwner.projectId` is nonzero, the holder of that `JBProjects` ERC-721 is the owner.
2. **Address ownership** -- If `projectId` is zero, `JBOwner.owner` is the owner directly.
3. **Delegated access** -- The owner can grant others access via `JBPermissions.setPermissionsFor(...)` using the configured `permissionId`.

The `permissionId` resets to 0 on every ownership transfer to prevent permission clashes.

## Install

```bash
npm install
```

## Develop

| Command | Description |
|---------|-------------|
| `forge build` | Compile contracts |
| `forge test` | Run tests |
| `forge coverage --match-path "./src/*.sol" --report lcov --report summary` | Generate coverage report |
