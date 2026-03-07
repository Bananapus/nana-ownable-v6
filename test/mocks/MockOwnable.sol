// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {JBOwnable, JBOwnableOverrides} from "../../src/JBOwnable.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";

contract MockOwnable is JBOwnable {
    event ProtectedMethodCalled();

    uint256 permissionId;

    function setPermission(uint256 newPermissionId) external {
        permissionId = newPermissionId;
    }

    constructor(
        IJBProjects projects,
        IJBPermissions permissions,
        address initialOwner,
        uint88 initialprojectIdOwner
    )
        JBOwnable(permissions, projects, initialOwner, initialprojectIdOwner)
    {}

    function protectedMethod() external onlyOwner {
        emit ProtectedMethodCalled();
    }

    function protectedMethodWithRequirePermission() external {
        uint256 projectId = jbOwner.projectId;

        _requirePermissionFrom({account: PROJECTS.ownerOf(projectId), projectId: projectId, permissionId: permissionId});

        emit ProtectedMethodCalled();
    }

    function protectedMethodWithRequireFromOwner() external {
        uint256 projectId = jbOwner.projectId;

        _requirePermissionFrom({account: PROJECTS.ownerOf(projectId), projectId: projectId, permissionId: permissionId});

        emit ProtectedMethodCalled();
    }
}
