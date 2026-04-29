// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MockOwnable} from "../mocks/MockOwnable.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";

contract PermissionDriftAfterProjectTransferTest is Test {
    JBPermissions internal permissions;
    JBProjects internal projects;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal operator = makeAddr("operator");

    function setUp() public {
        permissions = new JBPermissions(address(0));
        projects = new JBProjects(address(this), address(0), address(0));
    }

    function test_operatorCannotInheritOwnerAccessAfterProjectNftTransfer() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        vm.prank(alice);
        ownable.setPermissionId(42);

        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 42;

        vm.prank(bob);
        permissions.setPermissionsFor(
            bob, JBPermissionsData({operator: operator, projectId: 0, permissionIds: permissionIds})
        );

        vm.prank(alice);
        projects.transferFrom(alice, bob, projectId);

        assertEq(ownable.owner(), bob, "project NFT transfer makes bob the direct owner");
        (, uint88 storedProjectId, uint8 storedPermissionId) = ownable.jbOwner();
        assertEq(storedProjectId, projectId, "ownable remains project-owned");
        assertEq(storedPermissionId, 42, "old owner's permissionId survived the ownership change in storage");

        // After the fix, the stale permissionId is ignored because the resolved owner
        // (bob) differs from _permissionOwner (alice). The operator cannot seize ownership.
        vm.prank(operator);
        vm.expectRevert();
        ownable.transferOwnership(operator);

        // Bob is still the owner.
        assertEq(ownable.owner(), bob, "bob retains ownership; operator was blocked");
    }
}
