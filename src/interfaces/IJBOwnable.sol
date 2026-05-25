// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";

/// @notice Interface for Juicebox-aware ownership. Supports two modes: address-based (a fixed EOA/contract owns the
/// contract) or project-based (whoever holds a specific Juicebox project's ERC-721 NFT is the owner). The owner can
/// delegate access to other addresses via `JBPermissions`.
interface IJBOwnable {
    /// @notice Emitted when ownership is transferred to a new owner.
    /// @param previousOwner The address of the previous owner.
    /// @param newOwner The address of the new owner.
    /// @param caller The address that initiated the transfer.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner, address caller);

    /// @notice Emitted when the permission ID used for owner access is changed.
    /// @param newId The new permission ID.
    /// @param caller The address that changed the permission ID.
    event PermissionIdChanged(uint8 newId, address caller);

    /// @notice The `JBProjects` ERC-721 contract used to resolve project-based ownership.
    /// @return projects The `IJBProjects` contract.
    function PROJECTS() external view returns (IJBProjects projects);

    /// @notice The stored ownership state and delegation policy.
    /// @return owner The owner address (used when `projectId` is 0).
    /// @return projectId The Juicebox project whose NFT holder is the owner (0 if address-based ownership).
    /// @return permissionId The stored permission ID. It only delegates while the resolved owner matches the owner who
    /// last set it.
    function jbOwner() external view returns (address owner, uint88 projectId, uint8 permissionId);

    /// @notice Returns the current owner's address.
    /// @return owner The address of the current owner.
    function owner() external view returns (address owner);

    /// @notice Gives up ownership, making it impossible to call `onlyOwner` functions.
    function renounceOwnership() external;

    /// @notice Sets the permission ID the owner can use to give other addresses owner access.
    /// @param permissionId The permission ID to use for `onlyOwner`.
    function setPermissionId(uint8 permissionId) external;

    /// @notice Transfers ownership of this contract to a new address.
    /// @param newOwner The address to transfer ownership to.
    function transferOwnership(address newOwner) external;

    /// @notice Transfers ownership of this contract to a Juicebox project.
    /// @param projectId The ID of the project to transfer ownership to.
    function transferOwnershipToProject(uint256 projectId) external;
}
