// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";

/// @notice Provides Juicebox-aware ownership with support for project-based and address-based owners.
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

    /// @notice The contract that mints ERC-721s representing project ownership.
    /// @return projects The `IJBProjects` contract.
    function PROJECTS() external view returns (IJBProjects projects);

    /// @notice This contract's owner information.
    /// @return owner The owner address (used when `projectId` is 0).
    /// @return projectId The ID of the Juicebox project whose owner is this contract's owner (0 if not project-owned).
    /// @return permissionId The permission ID the owner can use to grant other addresses owner access.
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
