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
/// NFT). A project-based owner can delegate access by configuring a `permissionId` in `JBPermissions`; address-based
/// ownership is direct-owner-only.
/// @dev Project NFT transfers do not update stored owner data. A nonzero `permissionId` is only effective while the
/// resolved owner still equals `_permissionOwner`, the owner who last set that ID. If the NFT leaves and later returns
/// to that owner, their still-granted delegate permissions become effective again.
abstract contract JBOwnableOverrides is Context, JBPermissioned, IJBOwnable {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    /// @notice Thrown when address-based ownership tries to enable `JBPermissions` delegation.
    /// @param owner The address-based owner.
    /// @param permissionId The nonzero permission ID being set.
    error JBOwnableOverrides_AddressOwnerCannotSetPermissionId(address owner, uint8 permissionId);

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

    /// @notice The resolved owner address at the time `permissionId` was last set.
    /// @dev Used to ignore delegated permissions while project ownership is held by someone else.
    address internal _permissionOwner;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @dev To restrict access to a Juicebox project's owner, pass that project's ID as the `initialProjectIdOwner` and
    /// the zero address as the `initialOwner`.
    /// To restrict access to a specific address, pass it as `initialOwner` and `0` as `initialProjectIdOwner`.
    /// @dev Project-based owners can give owner access to other addresses through the `permissions` contract.
    /// Address-based owners cannot delegate owner access because `JBPermissions` project ID `0` is the wildcard
    /// project namespace.
    /// @dev If `initialProjectIdOwner` references an unminted project, `owner()` resolves to `address(0)` and
    /// owner-gated calls revert until that project is created. The first account to mint that project becomes the
    /// effective owner, so deployers must control the mint sequence.
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

        // Require an initial owner. To deploy unowned on purpose, deploy with an address owner and call
        // `renounceOwnership()` from the inheriting constructor.
        if (initialProjectIdOwner == 0 && initialOwner == address(0)) {
            revert JBOwnableOverrides_InvalidNewOwner({newOwner: initialOwner, projectId: initialProjectIdOwner});
        }

        // Constructors may pre-bind ownership to a project that will be minted later. Until then, `owner()` returns
        // address(0); once minted, ownership follows whoever received that project NFT.
        _transferOwnership({newOwner: initialOwner, projectId: initialProjectIdOwner});
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the current owner's address. If ownership is project-based, this dynamically resolves to
    /// whoever holds the project's ERC-721 NFT right now.
    /// @dev If `projectId` is non-zero, resolves via `PROJECTS.ownerOf()`. If that call reverts, returns
    /// `address(0)`, making owner-gated functions fail closed.
    function owner() public view virtual returns (address) {
        JBOwner memory ownerInfo = jbOwner;

        if (ownerInfo.projectId == 0) {
            return ownerInfo.owner;
        }

        // Expose the project owner, or zero if the project's NFT cannot be read, instead of bubbling the revert.
        return _projectOwnerOf(ownerInfo.projectId);
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @notice Reverts if the caller is not the owner (or an authorized delegate when `permissionId` is set).
    /// @dev If `projectId` is non-zero and `PROJECTS.ownerOf()` reverts, the resolved owner is `address(0)`, causing
    /// all `_checkOwner` calls to revert.
    /// @dev A nonzero `permissionId` only delegates while the current resolved owner equals `_permissionOwner`.
    /// Project NFT transfers therefore disable delegation for the new holder until they call `setPermissionId()`;
    /// returning the NFT to the original `_permissionOwner` can reactivate their old delegate grants.
    function _checkOwner() internal view virtual {
        JBOwner memory ownerInfo = jbOwner;

        address resolvedOwner;
        if (ownerInfo.projectId == 0) {
            resolvedOwner = ownerInfo.owner;

            // Address-owned contracts do not have a safe project namespace in JBPermissions: project ID 0 is the
            // wildcard scope. Keep address-based ownership direct-owner-only.
            if (_msgSender() != resolvedOwner) {
                revert JBPermissioned.JBPermissioned_Unauthorized({
                    account: resolvedOwner, sender: _msgSender(), projectId: 0, permissionId: 0
                });
            }
            return;
        } else {
            // Resolve the project owner dynamically; unreadable projects fail closed to address(0).
            resolvedOwner = _projectOwnerOf(ownerInfo.projectId);
        }

        // Ignore the stored permission ID while the project NFT is held by a different owner than the one who set it.
        uint8 effectivePermissionId = ownerInfo.permissionId;
        if (effectivePermissionId != 0 && resolvedOwner != _permissionOwner) {
            effectivePermissionId = 0;
        }

        // When delegation is disabled or stale, bypass the permission system entirely.
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

    /// @notice Resolves the current holder of a project's ownership NFT, or `address(0)` if the project's NFT cannot
    /// be read.
    /// @dev Wraps `PROJECTS.ownerOf` in a try-catch so an unreadable project (for example an NFT that has not been
    /// minted yet) resolves to `address(0)` and owner-gated logic fails closed instead of bubbling the revert. The
    /// resolution lives in one place so the try-catch lives in a single function rather than at every call site and in
    /// every contract that inherits this.
    /// @param projectId The ID of the project whose owner to resolve.
    /// @return projectOwner The project's current owner, or `address(0)` if `PROJECTS.ownerOf` reverts.
    function _projectOwnerOf(uint256 projectId) internal view virtual returns (address projectOwner) {
        try PROJECTS.ownerOf(projectId) returns (address resolved) {
            projectOwner = resolved;
        } catch {
            projectOwner = address(0);
        }
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

    /// @notice Configures which `JBPermissions` permission ID grants delegate access to `onlyOwner` functions while
    /// this contract is project-owned. Set to 0 to disable delegation entirely.
    /// @dev Can only be called by the current owner. Address-owned contracts can only set `permissionId` to 0.
    /// Records the current owner so delegation is ignored while a different owner holds the project NFT.
    /// @param permissionId The permission ID to use for `onlyOwner` delegation.
    function setPermissionId(uint8 permissionId) public virtual override {
        _checkOwner();
        _setPermissionId(permissionId);
    }

    /// @notice Transfers ownership of this contract to a new address. Can only be called by the current owner.
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

    /// @notice Transfers ownership to a Juicebox project, whose ERC-721 NFT holder becomes the owner.
    /// @dev The `permissionId` is reset to 0 on transfer to prevent the previous owner's delegates from retaining
    /// access. The new project owner must call `setPermissionId()` to re-enable delegation.
    /// @dev The `projectId` must fit within a `uint88` and the project must already exist.
    /// @param projectId The ID of the project to transfer ownership to.
    function transferOwnershipToProject(uint256 projectId) public virtual override {
        _checkOwner();
        if (projectId == 0 || projectId > type(uint88).max) {
            revert JBOwnableOverrides_InvalidNewOwner({newOwner: address(0), projectId: projectId});
        }

        // Public project transfers require an already-minted project. Constructor pre-binding is the only path that
        // can point at a future project ID.
        if (projectId > PROJECTS.count()) {
            revert JBOwnableOverrides_ProjectDoesNotExist({projectId: projectId, projectCount: PROJECTS.count()});
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        _transferOwnership({newOwner: address(0), projectId: uint88(projectId)});
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice Emits the ownership transfer event after resolving the visible new owner address.
    /// @dev This function exists because some contracts need to deploy contracts for a project before the project's NFT
    /// has been minted, so the transfer event resolves the project's current owner at emission time.
    /// @param previousOwner The address of the previous owner.
    /// @param newOwner The address of the new owner (zero if transferring to a project).
    /// @param newProjectId The ID of the new owning project (zero if transferring to an address).
    function _emitTransferEvent(address previousOwner, address newOwner, uint88 newProjectId) internal virtual;

    /// @notice Sets the permission ID the current project owner can use to delegate owner access.
    /// @dev Internal function without access restriction. Address-owned contracts can only clear the permission ID.
    /// @param permissionId The permission ID to use for `onlyOwner`.
    function _setPermissionId(uint8 permissionId) internal virtual {
        if (jbOwner.projectId == 0 && permissionId != 0) {
            revert JBOwnableOverrides_AddressOwnerCannotSetPermissionId({
                owner: jbOwner.owner, permissionId: permissionId
            });
        }

        jbOwner.permissionId = permissionId;
        _permissionOwner = owner();
        emit PermissionIdChanged({newId: permissionId, caller: _msgSender()});
    }

    /// @notice Drop-in replacement for OpenZeppelin's `Ownable._transferOwnership(address)`.
    /// @param newOwner The address that should receive ownership of this contract.
    function _transferOwnership(address newOwner) internal virtual {
        _transferOwnership({newOwner: newOwner, projectId: 0});
    }

    /// @notice Transfers this contract's ownership to either an address (`newOwner`) or a Juicebox project
    /// (`projectId`).
    /// @dev Updates this contract's `JBOwner` owner information and resets the `JBOwner.permissionId`.
    /// @dev If both `newOwner` and `projectId` are set, this will revert.
    /// @dev Internal function without access restriction.
    /// @param newOwner The address that should become this contract's owner.
    /// @param projectId The ID of the project whose owner should become this contract's owner.
    function _transferOwnership(address newOwner, uint88 projectId) internal virtual {
        // Ownership has exactly one live mode: address owner, project owner, or neither after renounce.
        if (projectId != 0 && newOwner != address(0)) {
            revert JBOwnableOverrides_InvalidNewOwner({newOwner: newOwner, projectId: projectId});
        }
        // Snapshot the current owner configuration before replacing it.
        JBOwner memory ownerInfo = jbOwner;
        // Resolve the previous owner for the event; unreadable project ownership is reported as address(0).
        address oldOwner;
        if (ownerInfo.projectId == 0) {
            oldOwner = ownerInfo.owner;
        } else {
            oldOwner = _projectOwnerOf(ownerInfo.projectId);
        }
        // Explicit ownership transfers clear delegated access and the owner who authorized it.
        jbOwner = JBOwner({owner: newOwner, projectId: projectId, permissionId: 0});
        _permissionOwner = address(0);
        // Emit a transfer event with the new owner's address.
        _emitTransferEvent({previousOwner: oldOwner, newOwner: newOwner, newProjectId: projectId});
    }
}
