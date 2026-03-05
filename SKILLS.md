# nana-ownable-v6

## Purpose

Drop-in Juicebox-aware replacement for OpenZeppelin `Ownable` that lets a contract be owned by a Juicebox project (via its ERC-721) or a plain address, with delegated access through `JBPermissions`.

## Contracts

| Contract | Role |
|----------|------|
| `JBOwnable` | Concrete modifier (`onlyOwner`) and event emission for ownership transfers. |
| `JBOwnableOverrides` | Abstract base with ownership state, resolution, transfers, renunciation, and permission delegation. |

## Key Functions

| Function | Contract | What it does |
|----------|----------|--------------|
| `owner()` | `JBOwnableOverrides` | Returns the current owner address -- resolves project NFT holder if `projectId` is set. |
| `transferOwnership(address)` | `JBOwnableOverrides` | Transfers ownership to a new address. Resets `permissionId`. |
| `transferOwnershipToProject(uint256)` | `JBOwnableOverrides` | Transfers ownership to a Juicebox project. The project NFT holder becomes owner. |
| `renounceOwnership()` | `JBOwnableOverrides` | Permanently gives up ownership (sets owner to zero address, projectId to 0). |
| `setPermissionId(uint8)` | `JBOwnableOverrides` | Changes which `JBPermissions` permission ID grants delegated owner access. |
| `_checkOwner()` | `JBOwnableOverrides` | Internal view used by `onlyOwner`; calls `_requirePermissionFrom` against the resolved owner. |

## Integration Points

| Dependency | Import | Used For |
|------------|--------|----------|
| `nana-core-v6` | `IJBPermissions`, `JBPermissioned` | Permission checks for delegated access |
| `nana-core-v6` | `IJBProjects` | Resolving project NFT holder as owner |
| `@openzeppelin/contracts` | `Context` | `_msgSender()` support |

## Key Types

| Struct/Enum | Key Fields | Used In |
|-------------|------------|---------|
| `JBOwner` | `address owner`, `uint88 projectId`, `uint8 permissionId` | `JBOwnableOverrides.jbOwner` -- single storage slot (160+88+8=256 bits) |

## Gotchas

- You cannot set both `owner` and `projectId` to nonzero values simultaneously -- `_transferOwnership` reverts with `JBOwnableOverrides_InvalidNewOwner`.
- Constructor reverts if both `initialOwner` and `initialProjectIdOwner` are zero. To create an unowned contract, set an owner then call `renounceOwnership()` in the constructor body.
- `_transferOwnership` resets `permissionId` to 0 on every transfer, which revokes all previously delegated access.
- `projectId` is `uint88`, so project IDs above `type(uint88).max` are rejected by `transferOwnershipToProject`.

## Example Integration

```solidity
import {JBOwnable} from "@bananapus/ownable-v6/src/JBOwnable.sol";

contract MyHook is JBOwnable {
    constructor(
        IJBPermissions permissions,
        IJBProjects projects,
        uint88 projectId
    ) JBOwnable(permissions, projects, address(0), projectId) {}

    function restrictedAction() external onlyOwner {
        // Only the project NFT holder (or delegated addresses) can call this.
    }
}
```
