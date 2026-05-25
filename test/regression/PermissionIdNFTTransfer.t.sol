// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MockOwnable} from "../mocks/MockOwnable.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";

contract PermissionIdNFTTransferTest is Test {
    IJBProjects internal projects;
    IJBPermissions internal permissions;

    address internal seller = makeAddr("seller");
    address internal buyer = makeAddr("buyer");
    address internal buyerOperator = makeAddr("buyerOperator");

    function setUp() public {
        permissions = new JBPermissions(address(0));
        projects = new JBProjects(address(this), address(0), address(0));
    }

    function test_projectNftTransferInvalidatesStalePermissionId() external {
        uint256 projectId = projects.createFor(seller);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // Seller sets permissionId 30 while they own the project.
        vm.prank(seller);
        ownable.setPermissionId(30);

        // Buyer grants their own operator permissionId 30 for this project.
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 30;
        vm.prank(buyer);
        permissions.setPermissionsFor(
            buyer,
            // forge-lint: disable-next-line(unsafe-typecast)
            JBPermissionsData({operator: buyerOperator, projectId: uint56(projectId), permissionIds: permissionIds})
        );

        // Seller transfers the project NFT to buyer.
        vm.prank(seller);
        projects.transferFrom(seller, buyer, projectId);

        assertEq(ownable.owner(), buyer, "project NFT transfer changes the effective owner");

        // The stored permissionId remains 30, but it is stale because the owner changed since it was set.
        (,, uint8 inheritedPermissionId) = ownable.jbOwner();
        assertEq(inheritedPermissionId, 30, "struct still holds old permissionId");

        // The buyer's operator cannot use a permissionId that was set by the seller.
        vm.prank(buyerOperator);
        vm.expectRevert();
        ownable.protectedMethod();
    }

    function test_newOwnerCanSetOwnPermissionIdAndDelegateAccess() external {
        uint256 projectId = projects.createFor(seller);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // Seller sets permissionId 30 while they own the project.
        vm.prank(seller);
        ownable.setPermissionId(30);

        // Transfer the project NFT to buyer.
        vm.prank(seller);
        projects.transferFrom(seller, buyer, projectId);

        // Buyer grants their own operator permissionId 30 for this project.
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 30;
        vm.prank(buyer);
        permissions.setPermissionsFor(
            buyer,
            // forge-lint: disable-next-line(unsafe-typecast)
            JBPermissionsData({operator: buyerOperator, projectId: uint56(projectId), permissionIds: permissionIds})
        );

        // Buyer explicitly sets the permissionId on the ownable contract.
        // This updates _permissionOwner to the buyer, making the permissionId valid.
        vm.prank(buyer);
        ownable.setPermissionId(30);

        // The buyer's operator can now call the protected method.
        vm.prank(buyerOperator);
        ownable.protectedMethod();
    }
}
