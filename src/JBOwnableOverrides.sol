// SPDX-License-Identifier: MIT
// Juicebox variation on OpenZeppelin Ownable
pragma solidity 0.8.28;

import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {IJBOwnable} from "./interfaces/IJBOwnable.sol";
import {JBOwner} from "./structs/JBOwner.sol";

/// @notice Abstract base implementing Juicebox-aware ownership resolution, transfer, and permission delegation.
/// Ownership is either address-based (a fixed EOA/contract) or project-based (whoever holds the project's ERC-721
/// NFT). The owner can delegate access to other addresses by configuring a `permissionId` in `JBPermissions`.
/// @dev Stale permission detection: when ownership changes (e.g. project NFT transferred), the `permissionId` is
/// effectively ignored until the new owner explicitly re-sets it — preventing the previous owner's delegates from
/// retaining access.
abstract contract JBOwnableOverrides is Context, JBPermissioned, IJBOwnable {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    /// @notice Thrown when an ownership transfer or constructor input does not identify exactly one valid owner.
    /// @param newOwner The address owner being set.
    /// @param projectId The project owner ID being set.
    error JBOwnableOverrides_InvalidNewOwner(address newOwner, uint256 projectId);

    /// @notice Thrown when project-based ownership points to a project that has not been minted.
    /// @param projectId The project ID that was requested.
    /// @param projectCount The current number of minted projects.
    error JBOwnableOverrides_ProjectDoesNotExist(uint256 projectId, uint256 projectCount);

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice The `JBProjects` ERC-721 contract used to resolve project-based ownership.
    IJBProjects public immutable override PROJECTS;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The current ownership state — who owns this contract and how permission delegation is configured.
    JBOwner public override jbOwner;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice The resolved owner address at the time permissionId was last set.
    /// @dev Used to detect stale permissions after ownership changes (e.g., NFT transfer).
    address internal _permissionOwner;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @dev To restrict access to a Juicebox project's owner, pass that project's ID as the `initialProjectIdOwner` and
    /// the zero address as the `initialOwner`.
    /// To restrict access to a specific address, pass that address as the `initialOwner` and `0` as the
    /// `initialProjectIdOwner`.
    /// @dev The owner can give owner access to other addresses through the `permissions` contract.
    /// @dev If `initialProjectIdOwner` references a project ID that has not yet been minted, all ownership checks will
    /// revert until that project is created, leaving the contract unusable. Deployers must ensure that the referenced
    /// project is minted before or atomically with this contract's deployment — this is a deployment trust
    /// assumption.
    /// @param permissions A contract storing permissions. Assumed to be a valid deployment-time dependency.
    /// @param projects Mints ERC-721s that represent project ownership and transfers. Assumed to be a valid
    /// deployment-time dependency.
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

        // We force the inheriting contract to set an owner, as there is a low chance someone will use `JBOwnable` to
        // create an unowned contract.
        // It's more likely both were accidentally set to `0`. If you really want an unowned contract, set the owner to
        // an address and call `renounceOwnership()` in the constructor body.
        if (initialProjectIdOwner == 0 && initialOwner == address(0)) {
            revert JBOwnableOverrides_InvalidNewOwner({newOwner: initialOwner, projectId: initialProjectIdOwner});
        }

        // No explicit project existence check here — if `initialProjectIdOwner` refers to an unminted project,
        // `owner()` will resolve via `PROJECTS.ownerOf()`, which reverts for non-existent tokens. The try-catch
        // in `owner()` treats this as renounced (returns address(0)), effectively locking the contract until
        // the project is minted. This is acceptable because deployers control the constructor arguments.
        _transferOwnership({newOwner: initialOwner, projectId: initialProjectIdOwner});
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the current owner's address. If ownership is project-based, this dynamically resolves to
    /// whoever holds the project's ERC-721 NFT right now.
    /// @dev If `projectId` is non-zero, resolves via `PROJECTS.ownerOf()`. If that call reverts (e.g., burned NFT),
    /// returns `address(0)` — effectively treating the contract as renounced. `JBProjects` V6 has no burn function,
    /// so this is a defensive measure only.
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

    /// @notice Reverts if the caller is not the owner (or an authorized delegate when `permissionId` is set).
    /// @dev If `projectId` is non-zero and `PROJECTS.ownerOf()` reverts (e.g., burned NFT), the resolved owner is
    /// `address(0)`, causing all `_checkOwner` calls to revert — equivalent to a renounced contract.
    /// @dev Stale permission detection: if the resolved owner differs from `_permissionOwner` (set when
    /// `setPermissionId` was last called), delegation is disabled until the new owner re-configures it.
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

        // Detect stale permissions: if ownership changed since permissionId was set
        // (e.g., project NFT transferred), treat permissionId as 0 (direct-owner-only).
        uint8 effectivePermissionId = ownerInfo.permissionId;
        if (effectivePermissionId != 0 && resolvedOwner != _permissionOwner) {
            effectivePermissionId = 0;
        }

        // When permissionId is 0 (direct-owner-only mode), bypass the permission system entirely.
        // This ensures ROOT operators cannot act as owner when delegation is disabled.
        if (effectivePermissionId == 0) {
            if (_msgSender() != resolvedOwner) {
                revert JBPermissioned.JBPermissioned_Unauthorized({
                    account: resolvedOwner, sender: _msgSender(), projectId: ownerInfo.projectId, permissionId: 0
                });
            }
            return;
        }

        _requirePermissionFrom({
            account: resolvedOwner, projectId: ownerInfo.projectId, permissionId: effectivePermissionId
        });
    }

    //*********************************************************************//
    // ---------------------- public transactions ------------------------ //
    //*********************************************************************//

    /// @notice Permanently gives up ownership. After this, no address can call `onlyOwner` functions.
    /// @dev Can only be called by the current owner. This is irreversible.
    function renounceOwnership() public virtual override {
        _checkOwner();
        _transferOwnership({newOwner: address(0), projectId: 0});
    }

    /// @notice Configures which `JBPermissions` permission ID grants delegate access to `onlyOwner` functions.
    /// Set to 0 to disable delegation entirely (only the direct owner can call).
    /// @dev Can only be called by the current owner. Records the current owner so stale permissions are detected
    /// if ownership later changes.
    /// @param permissionId The permission ID to use for `onlyOwner` delegation.
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
            revert JBOwnableOverrides_InvalidNewOwner({newOwner: newOwner, projectId: 0});
        }

        _transferOwnership({newOwner: newOwner, projectId: 0});
    }

    /// @notice Transfers ownership to a Juicebox project — whoever holds that project's ERC-721 NFT becomes the
    /// owner.
    /// @dev The `permissionId` is reset to 0 on transfer to prevent the previous owner's delegates from retaining
    /// access. The new project owner must call `setPermissionId()` to re-enable delegation.
    /// @dev The `projectId` must fit within a `uint88` and the project must already exist.
    /// @param projectId The ID of the project to transfer ownership to.
    function transferOwnershipToProject(uint256 projectId) public virtual override {
        _checkOwner();
        if (projectId == 0 || projectId > type(uint88).max) {
            revert JBOwnableOverrides_InvalidNewOwner({newOwner: address(0), projectId: projectId});
        }

        // Make sure the project exists to prevent permanent loss of contract control.
        if (projectId > PROJECTS.count()) {
            revert JBOwnableOverrides_ProjectDoesNotExist({projectId: projectId, projectCount: PROJECTS.count()});
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        _transferOwnership({newOwner: address(0), projectId: uint88(projectId)});
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
        _permissionOwner = owner();
        emit PermissionIdChanged({newId: permissionId, caller: _msgSender()});
    }

    /// @notice Drop-in replacement for OpenZeppelin's `Ownable._transferOwnership(address)`.
    /// @param newOwner The address that should receive ownership of this contract.
    function _transferOwnership(address newOwner) internal virtual {
        _transferOwnership({newOwner: newOwner, projectId: 0});
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
            revert JBOwnableOverrides_InvalidNewOwner({newOwner: newOwner, projectId: projectId});
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
        _permissionOwner = address(0);
        // Emit a transfer event with the new owner's address.
        _emitTransferEvent({previousOwner: oldOwner, newOwner: newOwner, newProjectId: projectId});
    }
}
