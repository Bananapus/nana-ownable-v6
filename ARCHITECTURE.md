# nana-ownable-v6 — Architecture

## Purpose

Juicebox-aware ownership module. Extends OpenZeppelin's Ownable pattern to support ownership by either a Juicebox project (via ERC-721) or a direct address, with permission delegation through JBPermissions. The primary use case is contracts like `JB721TiersHook` that inherit `JBOwnable` so they can be owned by a Juicebox project rather than just an EOA -- ownership automatically follows the project's ERC-721 token without requiring manual transfers when the project changes hands.

## Contract Map

```
src/
├── JBOwnable.sol            — Concrete ownable with constructor
├── JBOwnableOverrides.sol   — Abstract base with onlyOwner modifier logic
├── interfaces/
│   └── IJBOwnable.sol       — Interface for ownership queries and transfers
└── structs/
    └── JBOwner.sol          — Owner struct: {owner, projectId, permissionId}
```

## Ownership Model

```
JBOwner {
  address owner;       — Direct owner address (if projectId == 0)
  uint88 projectId;    — JB project ID whose NFT holder is owner (if != 0)
  uint8 permissionId;  — Permission ID that grants owner access via JBPermissions
}

Resolution order:
1. If projectId != 0 → owner = JBProjects.ownerOf(projectId)
2. If projectId == 0 → owner = JBOwner.owner address
3. Additional access via JBPermissions.hasPermission(operator, owner, projectId, permissionId)
```

## Key Operations

### Ownership Transfer
```
Current owner → transferOwnership(newOwner)
  → Can transfer to address or project ID
  → Emits OwnershipTransferred

Current owner → renounceOwnership()
  → Sets owner to address(0), projectId to 0
  → Permanently disables owner-only functions
```

## Design Decisions

### Project-as-owner instead of plain OpenZeppelin Ownable
OpenZeppelin's `Ownable` binds ownership to a single address. In Juicebox, project ownership is represented by an ERC-721 (`JBProjects`), and the owner of that NFT can change over time. `JBOwnable` resolves ownership dynamically via `PROJECTS.ownerOf(projectId)`, so any contract owned by a project automatically tracks whoever holds the project NFT. This avoids the need to manually call `transferOwnership` on every peripheral contract when a project changes hands.

### `permissionId` in the owner struct
The `JBOwner` struct includes a `uint8 permissionId` that the owner can configure via `setPermissionId()`. This lets the owner delegate access to specific addresses through `JBPermissions` without transferring ownership itself. For example, a project owner can grant a multisig or automation contract the ability to call `onlyOwner` functions on a hook without giving up project ownership. The permission ID is reset to 0 on every ownership transfer to prevent stale permission grants from carrying over to new owners.

### Abstract base with concrete modifier
`JBOwnableOverrides` is abstract and omits the `onlyOwner` modifier. The concrete `JBOwnable` adds it. This split exists because some inheriting contracts (like hooks deployed before a project NFT is minted) need to customize `_emitTransferEvent` -- the abstract base lets them override the event emission while reusing all ownership resolution and transfer logic.

### Struct packing
`JBOwner` packs `address owner` (160 bits), `uint88 projectId`, and `uint8 permissionId` into a single 256-bit storage slot. This means all ownership reads and writes cost one `SLOAD`/`SSTORE`, which matters because `_checkOwner` runs on every guarded call.

## Dependencies
- `@bananapus/core-v6` — JBPermissioned, IJBProjects, IJBPermissions
- `@openzeppelin/contracts` — Context
