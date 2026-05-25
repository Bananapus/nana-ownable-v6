// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MockOwnable} from "../mocks/MockOwnable.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";

contract ProjectTransferPermissionPolicyTest is Test {
    JBPermissions internal permissions;
    JBProjects internal projects;

    address internal seller = makeAddr("seller");
    address internal buyer = makeAddr("buyer");
    address internal operator = makeAddr("operator");

    function setUp() public {
        permissions = new JBPermissions(address(0));
        projects = new JBProjects(address(this), address(0), address(0));
    }

    function test_stalePermissionIdAfterProjectTransferBlocksBuyerOperator() public {
        uint256 projectId = projects.createFor(seller);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // The seller chooses a non-root ecosystem permission as this ownable's owner-equivalent permission.
        vm.prank(seller);
        ownable.setPermissionId(30);

        // The buyer has independently delegated permission 30 across their projects for unrelated operations.
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 30;

        vm.prank(buyer);
        permissions.setPermissionsFor(
            buyer, JBPermissionsData({operator: operator, projectId: 0, permissionIds: permissionIds})
        );

        // Buying/transferring the project NFT changes the effective owner, but does not reset permissionId in storage.
        vm.prank(seller);
        projects.transferFrom(seller, buyer, projectId);

        assertEq(ownable.owner(), buyer, "buyer is now the effective owner");

        (,, uint8 inheritedPermissionId) = ownable.jbOwner();
        assertEq(inheritedPermissionId, 30, "seller-selected permission policy persists in storage");

        // The stale permissionId is ignored because the resolved owner (buyer) differs from _permissionOwner (seller).
        // The operator is blocked.
        vm.prank(operator);
        vm.expectRevert();
        ownable.protectedMethod();
    }
}
