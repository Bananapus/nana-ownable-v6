# nana-ownable-v6 — Architecture

## Purpose

Juicebox-aware ownership module. Extends OpenZeppelin's Ownable pattern to support ownership by either a Juicebox project (via ERC-721) or a direct address, with permission delegation through JBPermissions.

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

## Dependencies
- `@bananapus/core-v6` — JBPermissioned, IJBProjects, IJBPermissions
- `@openzeppelin/contracts` — Context
