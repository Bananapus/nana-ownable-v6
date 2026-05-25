// SPDX-License-Identifier: MIT
// Juicebox variation on OpenZeppelin Ownable
pragma solidity 0.8.28;

import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";

import {JBOwnableOverrides} from "./JBOwnableOverrides.sol";

/// @notice Juicebox-aware ownership for any contract. Inherit this and apply the `onlyOwner` modifier to restrict
/// functions to the project owner, a fixed address, or an effective delegate authorized through `JBPermissions`.
/// @dev Ownership resolves dynamically: if `JBOwner.projectId` is set, the holder of that project's ERC-721 NFT is
/// the owner. If `projectId` is 0, the stored `JBOwner.owner` address is used instead. The owner can delegate access
/// to other addresses by setting a `permissionId` and granting that permission through `JBPermissions`.
contract JBOwnable is JBOwnableOverrides {
    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @dev To make a Juicebox project's owner this contract's owner, pass that project's ID as the
    /// `initialProjectIdOwner`.
    /// @dev To make a specific address the owner, pass that address as the `initialOwner` and `0` as the
    /// `initialProjectIdOwner`.
    /// @dev The owner can give other addresses owner access through the `permissions` contract.
    /// @param permissions A contract storing permissions.
    /// @param projects Mints ERC-721s that represent project ownership and transfers.
    /// @param initialOwner An address with owner access (until ownership is transferred).
    /// @param initialProjectIdOwner The ID of the Juicebox project whose owner has owner access (until ownership is
    /// transferred).
    constructor(
        IJBPermissions permissions,
        IJBProjects projects,
        address initialOwner,
        uint88 initialProjectIdOwner
    )
        JBOwnableOverrides(permissions, projects, initialOwner, initialProjectIdOwner)
    {}

    //*********************************************************************//
    // --------------------------- modifiers ----------------------------- //
    //*********************************************************************//

    /// @notice Reverts if called by an address without owner access.
    modifier onlyOwner() virtual {
        _checkOwner();
        _;
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice Emits the ownership transfer event after resolving the visible new owner address.
    /// @dev Constructor pre-binding can point ownership at a project before the project's NFT has been minted, so the
    /// event resolves the project's current owner at emission time.
    /// @dev Unlike `_transferOwnership` (which uses try-catch to resolve the *old* owner in case its project NFT is
    /// unreadable), this function resolves the *new* owner's current address for event purposes only.
    /// If the new project NFT does not exist yet, the event uses `address(0)` until ownership can resolve normally.
    function _emitTransferEvent(
        address previousOwner,
        address newOwner,
        uint88 newProjectId
    )
        internal
        virtual
        override
    {
        address resolvedNewOwner = newOwner;
        if (newProjectId != 0) {
            try PROJECTS.ownerOf(newProjectId) returns (address projectOwner) {
                resolvedNewOwner = projectOwner;
            } catch {
                // Pre-bound future projects have no visible owner yet, so the event reports address(0).
                resolvedNewOwner = address(0);
            }
        }

        emit OwnershipTransferred({previousOwner: previousOwner, newOwner: resolvedNewOwner, caller: _msgSender()});
    }
}
