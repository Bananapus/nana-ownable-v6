# nana-ownable-v6

Juicebox-aware ownership model that ties contract ownership to a Juicebox project NFT or an address, with delegated access through `JBPermissions`.

This is a variation on OpenZeppelin [`Ownable`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol) that adds:

- The ability to transfer contract ownership to a Juicebox project instead of a specific address.
- The ability to grant other addresses `onlyOwner` access using `JBPermissions`.
- `JBPermissioned` modifiers with support for OpenZeppelin `Context` (enabling optional meta-transaction support).

All features are backwards compatible with OpenZeppelin `Ownable`. This should be a drop-in replacement. Only use `JBOwnableOverrides` if you are overriding OpenZeppelin `Ownable` v4.7.0 or higher.

Forked from [`jbx-protocol/juice-ownable`](https://github.com/jbx-protocol/juice-ownable).

_If you have questions, take a look at the [core protocol contracts](https://github.com/Bananapus/nana-core) and the [documentation](https://docs.juicebox.money/) first, or reach out on [Discord](https://discord.com/invite/ErQYmth4dS)._

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
