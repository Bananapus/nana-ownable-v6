// SPDX-License-Identifier: MIT
// Juicebox variation on OpenZeppelin Ownable
pragma solidity ^0.8.26;

import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {IJBOwnable} from "./interfaces/IJBOwnable.sol";
import {JBOwner} from "./structs/JBOwner.sol";

/// @notice An abstract base for `JBOwnable`, which restricts functions so they can only be called by a Juicebox
/// project's owner or a specific owner address. The owner can give access permission to other addresses with
/// `JBPermissions`.
abstract contract JBOwnableOverrides is Context, JBPermissioned, IJBOwnable {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBOwnableOverrides_InvalidNewOwner();
    error JBOwnableOverrides_ProjectDoesNotExist();
    error JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner();

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice Mints ERC-721s that represent project ownership and transfers.
    IJBProjects public immutable override PROJECTS;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice This contract's owner information.
    JBOwner public override jbOwner;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @dev To restrict access to a Juicebox project's owner, pass that project's ID as the `initialProjectIdOwner` and
    /// the zero address as the `initialOwner`.
    /// To restrict access to a specific address, pass that address as the `initialOwner` and `0` as the
    /// `initialProjectIdOwner`.
    /// @dev The owner can give owner access to other addresses through the `permissions` contract.
    /// @param permissions A contract storing permissions.
    /// @param projects Mints ERC-721s that represent project ownership and transfers.
    /// @param initialOwner The owner if the `initialProjectIdOwner` is 0 (until ownership is transferred).
    /// @param initialProjectIdOwner The ID of the Juicebox project whose owner is this contract's owner (until
    /// ownership is transferred).
    constructor(
        IJBPermissions permissions,
        IJBProjects projects,
        address initialOwner,
        uint88 initialProjectIdOwner
    )
        JBPermissioned(permissions)
    {
        PROJECTS = projects;

        // If using project-based ownership, the PROJECTS contract must be provided.
        // Deploying with projects=address(0) and a non-zero projectId would permanently disable
        // ownership resolution, as all ownerOf() calls would revert on the zero address.
        if (initialProjectIdOwner != 0 && address(projects) == address(0)) {
            revert JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner();
        }

        // We force the inheriting contract to set an owner, as there is a low chance someone will use `JBOwnable` to
        // create an unowned contract.
        // It's more likely both were accidentally set to `0`. If you really want an unowned contract, set the owner to
        // an address and call `renounceOwnership()` in the constructor body.
        if (initialProjectIdOwner == 0 && initialOwner == address(0)) {
            revert JBOwnableOverrides_InvalidNewOwner();
        }

        _transferOwnership(initialOwner, initialProjectIdOwner);
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the owner's address based on this contract's `JBOwner`.
    /// @dev If `projectId` is non-zero, resolves via `PROJECTS.ownerOf()`. If that call reverts (e.g., because the
    /// project NFT was burned or invalidated), returns `address(0)` — effectively treating the contract as renounced.
    /// @dev **Assumption:** `JBProjects` V6 has no burn function, so this scenario cannot occur under normal
    /// conditions. The try-catch is a defensive measure against hypothetical future changes to `JBProjects` or
    /// unexpected ERC-721 behavior.
    function owner() public view virtual returns (address) {
        JBOwner memory ownerInfo = jbOwner;

        if (ownerInfo.projectId == 0) {
            return ownerInfo.owner;
        }

        // Use try-catch to gracefully handle the case where the project NFT no longer exists.
        // If ownerOf reverts, the contract is effectively renounced (returns address(0)).
        try PROJECTS.ownerOf(ownerInfo.projectId) returns (address projectOwner) {
            return projectOwner;
        } catch {
            return address(0);
        }
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @notice Reverts if the sender is not the owner.
    /// @dev If `projectId` is non-zero and `PROJECTS.ownerOf()` reverts (e.g., burned NFT), the resolved owner is
    /// `address(0)`, causing all `_checkOwner` calls to revert — equivalent to a renounced contract.
    function _checkOwner() internal view virtual {
        JBOwner memory ownerInfo = jbOwner;

        address resolvedOwner;
        if (ownerInfo.projectId == 0) {
            resolvedOwner = ownerInfo.owner;
        } else {
            // Use try-catch to gracefully handle the case where the project NFT no longer exists.
            try PROJECTS.ownerOf(ownerInfo.projectId) returns (address projectOwner) {
                resolvedOwner = projectOwner;
            } catch {
                resolvedOwner = address(0);
            }
        }

        _requirePermissionFrom({
            account: resolvedOwner, projectId: ownerInfo.projectId, permissionId: ownerInfo.permissionId
        });
    }

    //*********************************************************************//
    // ---------------------- public transactions ------------------------ //
    //*********************************************************************//

    /// @notice Gives up ownership of this contract, making it impossible to call `onlyOwner` and `_checkOwner`
    /// functions.
    /// @dev This can only be called by the current owner.
    function renounceOwnership() public virtual override {
        _checkOwner();
        _transferOwnership(address(0), 0);
    }

    /// @notice Sets the permission ID the owner can use to give other addresses owner access.
    /// @dev This can only be called by the current owner.
    /// @param permissionId The permission ID to use for `onlyOwner`.
    function setPermissionId(uint8 permissionId) public virtual override {
        _checkOwner();
        _setPermissionId(permissionId);
    }

    /// @notice Transfers ownership of this contract to a new address (the `newOwner`). Can only be called by the
    /// current owner.
    /// @dev The `permissionId` is reset to 0 on transfer to prevent permission clashes for the new owner.
    /// The new owner must explicitly call `setPermissionId()` to configure owner-level permission delegation.
    /// @param newOwner The address to transfer ownership to.
    function transferOwnership(address newOwner) public virtual override {
        _checkOwner();
        if (newOwner == address(0)) {
            revert JBOwnableOverrides_InvalidNewOwner();
        }

        _transferOwnership(newOwner, 0);
    }

    /// @notice Transfer ownership of this contract to a new Juicebox project.
    /// @dev The `permissionId` is reset to 0 on transfer to prevent permission clashes for the new project owner.
    /// The new owner must explicitly call `setPermissionId()` to configure owner-level permission delegation.
    /// @dev The `projectId` must fit within a `uint88`.
    /// @param projectId The ID of the project to transfer ownership to.
    function transferOwnershipToProject(uint256 projectId) public virtual override {
        _checkOwner();
        if (projectId == 0 || projectId > type(uint88).max) {
            revert JBOwnableOverrides_InvalidNewOwner();
        }

        // Make sure the project exists to prevent permanent loss of contract control.
        if (projectId > PROJECTS.count()) {
            revert JBOwnableOverrides_ProjectDoesNotExist();
        }

        _transferOwnership(address(0), uint88(projectId));
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice Either `newOwner` or `newProjectId` is non-zero or both are zero. But they can never both be non-zero.
    /// @dev This function exists because some contracts need to deploy contracts for a project before the project's NFT
    /// has been minted, so the transfer event resolves the project's current owner at emission time.
    /// @param previousOwner The address of the previous owner.
    /// @param newOwner The address of the new owner (zero if transferring to a project).
    /// @param newProjectId The ID of the new owning project (zero if transferring to an address).
    function _emitTransferEvent(address previousOwner, address newOwner, uint88 newProjectId) internal virtual;

    /// @notice Sets the permission ID the owner can use to give other addresses owner access.
    /// @dev Internal function without access restriction.
    /// @param permissionId The permission ID to use for `onlyOwner`.
    function _setPermissionId(uint8 permissionId) internal virtual {
        jbOwner.permissionId = permissionId;
        emit PermissionIdChanged({newId: permissionId, caller: msg.sender});
    }

    /// @notice Helper to allow for drop-in replacement of OpenZeppelin `Ownable`.
    /// @param newOwner The address that should receive ownership of this contract.
    function _transferOwnership(address newOwner) internal virtual {
        _transferOwnership(newOwner, 0);
    }

    /// @notice Transfers this contract's ownership to an address (`newOwner`) OR a Juicebox project (`projectId`).
    /// @dev Updates this contract's `JBOwner` owner information and resets the `JBOwner.permissionId`.
    /// @dev If both `newOwner` and `projectId` are set, this will revert.
    /// @dev Internal function without access restriction.
    /// @param newOwner The address that should become this contract's owner.
    /// @param projectId The ID of the project whose owner should become this contract's owner.
    function _transferOwnership(address newOwner, uint88 projectId) internal virtual {
        // Can't set both a new owner and a new project ID.
        if (projectId != 0 && newOwner != address(0)) {
            revert JBOwnableOverrides_InvalidNewOwner();
        }
        // Load the owner information from storage.
        JBOwner memory ownerInfo = jbOwner;
        // Get the address of the old owner. Use try-catch for project-based ownership in case the NFT was burned.
        address oldOwner;
        if (ownerInfo.projectId == 0) {
            oldOwner = ownerInfo.owner;
        } else {
            try PROJECTS.ownerOf(ownerInfo.projectId) returns (address projectOwner) {
                oldOwner = projectOwner;
            } catch {
                oldOwner = address(0);
            }
        }
        // Update the stored owner information to the new owner and reset the `permissionId`.
        // This is to prevent permissions clashes for the new user/owner.
        jbOwner = JBOwner({owner: newOwner, projectId: projectId, permissionId: 0});
        // Emit a transfer event with the new owner's address.
        _emitTransferEvent(oldOwner, newOwner, projectId);
    }
}
