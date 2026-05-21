// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";

import {JBOwnable} from "../../src/JBOwnable.sol";

/// @notice Minimal permission mock for ownership-state proofs that never exercise delegated authorization.
contract HalmosPermissions {
    function hasPermission(address, address, uint256, uint256, bool, bool) external pure returns (bool) {
        return false;
    }
}

/// @notice Minimal project NFT mock used to prove dynamic project-owner resolution.
contract HalmosProjects {
    mapping(uint256 projectId => address owner) internal _ownerOf;

    uint256 public count;

    /// @notice Sets a project's owner and grows `count` enough for `transferOwnershipToProject`.
    /// @param projectId The symbolic project ID to configure.
    /// @param owner The symbolic project NFT owner.
    function setOwner(uint256 projectId, address owner) external {
        _ownerOf[projectId] = owner;
        if (projectId > count) count = projectId;
    }

    /// @notice Resolves a project owner and matches ERC-721's revert-on-missing-token behavior.
    /// @param projectId The project ID to resolve.
    /// @return owner The configured project owner.
    function ownerOf(uint256 projectId) external view returns (address owner) {
        owner = _ownerOf[projectId];
        if (owner == address(0)) revert();
    }
}

/// @notice Small Halmos entrypoints for JBOwnable's ownership-state transitions.
/// @dev The checks focus on the local state machine. Broader `JBPermissions` authorization behavior stays covered by
/// Foundry regression and invariant tests because it depends on the core permissions contract.
contract JBOwnableHalmos is JBOwnable {
    HalmosProjects internal immutable PROJECTS_MOCK;

    constructor()
        JBOwnable(
            IJBPermissions(address(new HalmosPermissions())),
            IJBProjects(address(new HalmosProjects())),
            address(this),
            0
        )
    {
        PROJECTS_MOCK = HalmosProjects(address(PROJECTS));
    }

    /// @notice Exposes the internal ownership transfer helper for revert-path proofs.
    /// @param newOwner The address owner to set.
    /// @param projectId The project owner to set.
    function exposedTransferOwnership(address newOwner, uint88 projectId) external {
        _transferOwnership({newOwner: newOwner, projectId: projectId});
    }

    /// @notice Proves address ownership transfer resets project ownership and delegation.
    /// @param newOwner The symbolic address receiving ownership.
    /// @param permissionId A prior symbolic delegated permission ID.
    function check_addressTransferResetsProjectAndPermission(address newOwner, uint8 permissionId) public {
        if (newOwner == address(0)) return;

        _setPermissionId({permissionId: permissionId});
        _transferOwnership({newOwner: newOwner, projectId: 0});

        (address storedOwner, uint88 projectId, uint8 storedPermissionId) = this.jbOwner();

        assert(storedOwner == newOwner);
        assert(projectId == 0);
        assert(storedPermissionId == 0);
        assert(owner() == newOwner);
    }

    /// @notice Proves project ownership transfer clears address ownership and resolves through the project NFT.
    /// @param projectId The symbolic project receiving ownership.
    /// @param projectOwner The symbolic holder of that project's NFT.
    /// @param permissionId A prior symbolic delegated permission ID.
    function check_projectTransferResetsAddressAndPermission(
        uint88 projectId,
        address projectOwner,
        uint8 permissionId
    )
        public
    {
        if (projectId == 0 || projectOwner == address(0)) return;

        PROJECTS_MOCK.setOwner({projectId: projectId, owner: projectOwner});
        _setPermissionId({permissionId: permissionId});
        _transferOwnership({newOwner: address(0), projectId: projectId});

        (address storedOwner, uint88 storedProjectId, uint8 storedPermissionId) = this.jbOwner();

        assert(storedOwner == address(0));
        assert(storedProjectId == projectId);
        assert(storedPermissionId == 0);
        assert(owner() == projectOwner);
    }

    /// @notice Proves renouncing ownership clears both owner modes and delegation.
    /// @param permissionId A prior symbolic delegated permission ID.
    function check_renounceClearsOwnerProjectAndPermission(uint8 permissionId) public {
        _setPermissionId({permissionId: permissionId});
        _transferOwnership({newOwner: address(0), projectId: 0});

        (address storedOwner, uint88 projectId, uint8 storedPermissionId) = this.jbOwner();

        assert(storedOwner == address(0));
        assert(projectId == 0);
        assert(storedPermissionId == 0);
        assert(owner() == address(0));
    }

    /// @notice Proves ownership cannot be transferred to an address and project at the same time.
    /// @param newOwner The symbolic address owner.
    /// @param projectId The symbolic project owner.
    function check_dualOwnerTransferReverts(address newOwner, uint88 projectId) public {
        if (newOwner == address(0) || projectId == 0) return;

        try this.exposedTransferOwnership({newOwner: newOwner, projectId: projectId}) {
            assert(false);
        } catch {
            assert(true);
        }
    }

    /// @notice Proves the public project-transfer path rejects project IDs that cannot fit in stored owner state.
    /// @param projectId The symbolic project ID.
    function check_publicProjectTransferRejectsTooLargeProjectId(uint256 projectId) public {
        if (projectId <= type(uint88).max) return;

        try this.transferOwnershipToProject({projectId: projectId}) {
            assert(false);
        } catch {
            assert(true);
        }
    }

    /// @notice Proves the public address-transfer path rejects the zero address.
    function check_publicAddressTransferRejectsZeroOwner() public {
        try this.transferOwnership({newOwner: address(0)}) {
            assert(false);
        } catch {
            assert(true);
        }
    }
}
