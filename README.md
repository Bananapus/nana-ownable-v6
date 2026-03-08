# Juicebox Ownable

Ownership that follows the project, not a person. Transfer control of any contract to a Juicebox project NFT, and anyone the project owner delegates through `JBPermissions` can act as owner.

This is a variation on OpenZeppelin [`Ownable`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol) that adds:

- The ability to transfer contract ownership to a Juicebox project instead of a specific address. When owned by a project, ownership dynamically follows whoever holds that project's ERC-721 NFT -- no on-chain update needed.
- The ability to grant other addresses `onlyOwner` access using `JBPermissions`, with a configurable `permissionId`.
- `JBPermissioned` base class with support for OpenZeppelin `Context` (enabling optional meta-transaction support).

All features are backwards compatible with OpenZeppelin `Ownable`. `JBOwnable` is a drop-in replacement: it provides the same `onlyOwner` modifier, `owner()` view, `transferOwnership(address)`, and `renounceOwnership()` functions.

Forked from [`jbx-protocol/juice-ownable`](https://github.com/jbx-protocol/juice-ownable).

_If you have questions, take a look at the [core protocol contracts](https://github.com/Bananapus/nana-core-v6) and the [documentation](https://docs.juicebox.money/) first, or reach out on [Discord](https://discord.com/invite/ErQYmth4dS)._

## Architecture

```
JBOwnable
  └── JBOwnableOverrides (abstract)
        ├── Context (OpenZeppelin)
        ├── JBPermissioned (nana-core-v6)
        └── IJBOwnable (interface)
```

| Contract | Description |
|----------|-------------|
| [`JBOwnable`](src/JBOwnable.sol) | Concrete implementation. Provides the `onlyOwner` modifier and emits `OwnershipTransferred` events (resolving project NFT holders at emission time). Inherit this in your contract. |
| [`JBOwnableOverrides`](src/JBOwnableOverrides.sol) | Abstract base containing all ownership logic: owner resolution, transfers, renunciation, permission delegation, and internal helpers. Use this directly only if you need to customize `_emitTransferEvent` (e.g., when deploying contracts before the project NFT is minted). |

### Supporting Types

| Type | Location | Description |
|------|----------|-------------|
| [`JBOwner`](src/structs/JBOwner.sol) | `src/structs/` | Struct packing `address owner` (160 bits), `uint88 projectId` (88 bits), and `uint8 permissionId` (8 bits) into a single 256-bit storage slot. |
| [`IJBOwnable`](src/interfaces/IJBOwnable.sol) | `src/interfaces/` | Interface exposing ownership queries, transfers, renunciation, permission ID management, and events. |

### Ownership Modes

1. **Project ownership** -- If `JBOwner.projectId` is nonzero, the current holder of that `JBProjects` ERC-721 is the owner. Ownership automatically follows the NFT: when the NFT is transferred, `owner()` immediately reflects the new holder without any additional transaction.
2. **Address ownership** -- If `projectId` is zero, `JBOwner.owner` is the owner directly.
3. **Delegated access** -- The owner can grant other addresses access via `JBPermissions.setPermissionsFor(...)` using the configured `permissionId`. The owner must first call `setPermissionId(uint8)` to set which permission ID represents owner-level access.
4. **Renounced** -- After calling `renounceOwnership()`, both `owner` and `projectId` are set to zero. No one can call `onlyOwner` functions. This is irreversible.

The `permissionId` resets to 0 on every ownership transfer to prevent permission clashes for the new owner.

### Events

| Event | Emitted By |
|-------|-----------|
| `OwnershipTransferred(address indexed previousOwner, address indexed newOwner, address caller)` | `_emitTransferEvent` (called on every ownership change) |
| `PermissionIdChanged(uint8 newId, address caller)` | `_setPermissionId` |

### Errors

| Error | Thrown When |
|-------|-----------|
| `JBOwnableOverrides_InvalidNewOwner()` | Constructor receives both zero owner and zero projectId; `transferOwnership` receives zero address; `transferOwnershipToProject` receives zero or overflow projectId; `_transferOwnership` receives both non-zero owner and non-zero projectId. |
| `JBOwnableOverrides_ProjectDoesNotExist()` | `transferOwnershipToProject` receives a projectId greater than `PROJECTS.count()`. |
| `JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner()` | Constructor receives a non-zero `initialProjectIdOwner` with `projects` set to `address(0)`. |

## How Ownership Resolution Works

When `_checkOwner()` is called (by the `onlyOwner` modifier), it:

1. Reads the `JBOwner` struct from storage.
2. Resolves the owner address: if `projectId != 0`, calls `PROJECTS.ownerOf(projectId)` via try-catch (returns `address(0)` if the call reverts, e.g., burned NFT); otherwise uses the stored `owner` address.
3. Calls `_requirePermissionFrom(account, projectId, permissionId)` from `JBPermissioned`, which passes if the caller is:
   - The resolved owner address, OR
   - An address granted the configured `permissionId` on the relevant project via `JBPermissions`, OR
   - An address granted the ROOT permission (permission ID 1) on the relevant project via `JBPermissions`.

## How Delegated Access Works

1. The owner calls `setPermissionId(uint8)` on the `JBOwnable` contract to configure which permission ID represents owner-level access.
2. The owner calls `JBPermissions.setPermissionsFor(...)` to grant that permission ID to specific addresses on the relevant project.
3. Those addresses can now call `onlyOwner` functions.
4. If the project NFT is transferred to a new holder, delegated permissions granted by the previous holder stop working -- the new holder must re-grant permissions.

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
