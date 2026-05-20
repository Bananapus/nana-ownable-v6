// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MockOwnable} from "../mocks/MockOwnable.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";

contract CodexNemesisPermissionReactivationTest is Test {
    IJBProjects internal projects;
    IJBPermissions internal permissions;

    address internal seller = makeAddr("seller");
    address internal buyer = makeAddr("buyer");
    address internal sellerOperator = makeAddr("sellerOperator");

    function setUp() public {
        permissions = new JBPermissions(address(0));
        projects = new JBProjects(address(this), address(0), address(0));
    }

    function test_projectReturnReactivatesOriginalOwnersOldDelegate() external {
        uint256 projectId = projects.createFor(seller);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        vm.prank(seller);
        ownable.setPermissionId(30);

        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 30;
        vm.prank(seller);
        permissions.setPermissionsFor(
            seller,
            // Safe: `projectId` comes from the mock projects counter in this test and is far below uint64 max.
            // forge-lint: disable-next-line(unsafe-typecast)
            JBPermissionsData({operator: sellerOperator, projectId: uint64(projectId), permissionIds: permissionIds})
        );

        vm.prank(seller);
        projects.transferFrom(seller, buyer, projectId);

        vm.prank(sellerOperator);
        vm.expectRevert();
        ownable.protectedMethod();

        vm.prank(buyer);
        projects.transferFrom(buyer, seller, projectId);

        vm.prank(sellerOperator);
        ownable.protectedMethod();

        vm.prank(sellerOperator);
        ownable.transferOwnership(sellerOperator);

        assertEq(ownable.owner(), sellerOperator);
    }
}
