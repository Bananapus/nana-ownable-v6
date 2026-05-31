// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";

import {JBOwnableOverrides} from "../../src/JBOwnableOverrides.sol";
import {MockOwnable} from "../mocks/MockOwnable.sol";

contract AddressOwnerPermissionPolicyTest is Test {
    JBPermissions internal permissions;
    JBProjects internal projects;

    address internal owner = makeAddr("owner");
    address internal rootOperator = makeAddr("rootOperator");
    address internal scopedOperator = makeAddr("scopedOperator");

    function setUp() public {
        permissions = new JBPermissions(address(0));
        projects = new JBProjects(address(this), address(0), address(0));
    }

    function test_addressOwnedContractsRejectNonzeroPermissionIds() public {
        MockOwnable ownable = new MockOwnable(projects, permissions, owner, 0);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                JBOwnableOverrides.JBOwnableOverrides_AddressOwnerCannotSetPermissionId.selector, owner, 42
            )
        );
        ownable.setPermissionId(42);

        vm.prank(owner);
        ownable.setPermissionId(0);

        (address storedOwner, uint88 projectId, uint8 permissionId) = ownable.jbOwner();
        assertEq(storedOwner, owner);
        assertEq(projectId, 0);
        assertEq(permissionId, 0);
    }

    function test_wildcardOperatorsDoNotControlAddressOwnedContracts() public {
        MockOwnable ownable = new MockOwnable(projects, permissions, owner, 0);

        uint8[] memory rootOnly = new uint8[](1);
        rootOnly[0] = JBPermissionIds.ROOT;

        vm.prank(owner);
        permissions.setPermissionsFor(
            owner, JBPermissionsData({operator: rootOperator, projectId: 0, permissionIds: rootOnly})
        );

        uint8[] memory permissionOnly = new uint8[](1);
        permissionOnly[0] = 42;

        vm.prank(owner);
        permissions.setPermissionsFor(
            owner, JBPermissionsData({operator: scopedOperator, projectId: 0, permissionIds: permissionOnly})
        );

        vm.prank(owner);
        ownable.protectedMethod();

        vm.prank(rootOperator);
        vm.expectRevert(
            abi.encodeWithSelector(JBPermissioned.JBPermissioned_Unauthorized.selector, owner, rootOperator, 0, 0)
        );
        ownable.protectedMethod();

        vm.prank(scopedOperator);
        vm.expectRevert(
            abi.encodeWithSelector(JBPermissioned.JBPermissioned_Unauthorized.selector, owner, scopedOperator, 0, 0)
        );
        ownable.protectedMethod();
    }
}
