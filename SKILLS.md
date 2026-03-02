# nana-ownable-v5 — AI Reference

## Purpose

Extends OpenZeppelin's `Ownable` pattern so that contract ownership can be held by a Juicebox project (via the `JBProjects` ERC-721 NFT) instead of just an EOA address. Integrates with `JBPermissions` for delegated owner access.

## Contracts

### JBOwnable (src/JBOwnable.sol)
Concrete contract. Provides the `onlyOwner` modifier and emits `OwnershipTransferred` events.

**Constructor:**
```solidity
constructor(IJBPermissions permissions, IJBProjects projects, address initialOwner, uint88 initialProjectIdOwner)
```

### JBOwnableOverrides (src/JBOwnableOverrides.sol)
Abstract base containing all ownership logic. Extends `JBPermissioned` and `Context`.

**State:**
- `IJBProjects public immutable PROJECTS`
- `JBOwner public jbOwner` — packed struct: `address owner`, `uint88 projectId`, `uint8 permissionId`

## Entry Points

```solidity
function owner() public view returns (address)
function transferOwnership(address newOwner) public
function transferOwnershipToProject(uint256 projectId) public
function renounceOwnership() public
function setPermissionId(uint8 permissionId) public
```

All mutating functions call `_checkOwner()` which uses `_requirePermissionFrom()`.

## Integration Points

- **JBPermissions**: Checked in `_checkOwner()` — the owner can grant other addresses access via `permissionId`.
- **JBProjects**: When `projectId != 0`, `PROJECTS.ownerOf(projectId)` determines the owner.
- **Drop-in replacement**: Any contract using OZ `Ownable` can switch to `JBOwnable` for project-based ownership.

## Key Patterns

- **Dual ownership mode**: EOA (projectId == 0) or project NFT holder (projectId != 0). Never both.
- **permissionId reset**: On every `_transferOwnership`, `permissionId` resets to 0 to prevent the new owner from inheriting the previous owner's permission delegations.
- **Constructor validation**: Reverts if both `initialOwner` and `initialProjectIdOwner` are zero (prevents accidentally unowned contracts).
- **JBOwner struct packing**: `address` (160 bits) + `uint88` (88 bits) + `uint8` (8 bits) = 256 bits = 1 storage slot.
