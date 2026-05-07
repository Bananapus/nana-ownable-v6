// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MockOwnable} from "../mocks/MockOwnable.sol";

import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";

contract RootPermissionBypassesPermissionIdZeroTest is Test {
    JBProjects internal projects;
    JBPermissions internal permissions;

    address internal alice = makeAddr("alice");
    address internal operator = makeAddr("operator");

    function setUp() public {
        permissions = new JBPermissions(address(0));
        projects = new JBProjects(address(this), address(0), address(0));
    }

    /// @notice After fix: ROOT operator is rejected when permissionId=0 (direct-owner-only mode).
    function test_rootPermissionRejectedWhenPermissionIdIsZero() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // Grant ROOT permission (id=1) to operator.
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 1;

        vm.prank(alice);
        permissions.setPermissionsFor(
            // forge-lint: disable-next-line(unsafe-typecast)
            alice,
            // forge-lint: disable-next-line(unsafe-typecast)
            JBPermissionsData({operator: operator, projectId: uint56(projectId), permissionIds: permissionIds})
        );

        (, uint88 storedProjectId, uint8 permissionId) = ownable.jbOwner();
        assertEq(storedProjectId, projectId);
        assertEq(permissionId, 0, "expected direct-owner-only mode");

        // Operator should be rejected when permissionId=0.
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(JBPermissioned.JBPermissioned_Unauthorized.selector, alice, operator, projectId, 0)
        );
        ownable.protectedMethod();
    }

    /// @notice Direct owner still works when permissionId=0.
    function test_directOwnerStillWorksWithPermissionIdZero() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        (, uint88 storedProjectId, uint8 permissionId) = ownable.jbOwner();
        assertEq(storedProjectId, projectId);
        assertEq(permissionId, 0);

        // Alice (project owner) should still be able to call the protected method.
        vm.prank(alice);
        ownable.protectedMethod();
    }

    /// @notice Non-zero permissionId still delegates correctly via the permission system.
    function test_delegatedOperatorWorksWhenPermissionIdNonZero() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // Set permissionId to 42 (non-zero = delegation enabled).
        vm.prank(alice);
        ownable.setPermissionId(42);

        // Grant permission 42 to operator.
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 42;

        vm.prank(alice);
        permissions.setPermissionsFor(
            // forge-lint: disable-next-line(unsafe-typecast)
            alice,
            // forge-lint: disable-next-line(unsafe-typecast)
            JBPermissionsData({operator: operator, projectId: uint56(projectId), permissionIds: permissionIds})
        );

        // Operator should succeed with matching permissionId.
        vm.prank(operator);
        ownable.protectedMethod();
    }
}
