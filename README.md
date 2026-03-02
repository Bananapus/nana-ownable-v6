# nana-ownable-v5

Drop-in replacement for OpenZeppelin `Ownable` that supports Juicebox project ownership and permission delegation via `JBPermissions`.

## Architecture

| Contract | Description |
|---|---|
| `src/JBOwnable.sol` | Concrete contract with `onlyOwner` modifier. Inherit this for new contracts. |
| `src/JBOwnableOverrides.sol` | Abstract base with all ownership logic. Use when overriding an existing `Ownable` dependency. |
| `src/interfaces/IJBOwnable.sol` | Interface for `JBOwnable`. |
| `src/structs/JBOwner.sol` | Struct: `address owner`, `uint88 projectId`, `uint8 permissionId`. |

### Ownership Model

Ownership is determined by a `JBOwner` struct:

1. If `projectId != 0`, the holder of the `JBProjects` NFT with that ID is the owner.
2. If `projectId == 0`, the `owner` address is the owner.
3. The owner can delegate access to other addresses via `JBPermissions` using `permissionId`.

The `permissionId` resets to 0 on every ownership transfer to prevent permission clashes.

## Install

```bash
npm install @bananapus/ownable
```

Or with Forge:

```bash
forge install Bananapus/nana-ownable
```

## Develop

```bash
npm ci && forge install
forge build
forge test
```
