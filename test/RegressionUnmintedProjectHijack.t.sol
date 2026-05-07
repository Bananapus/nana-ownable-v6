// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MockOwnable} from "./mocks/MockOwnable.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";

contract RegressionUnmintedProjectHijackTest is Test {
    IJBProjects internal projects;
    IJBPermissions internal permissions;

    address internal deployer = makeAddr("deployer");
    address internal attacker = makeAddr("attacker");
    address internal intendedOwner = makeAddr("intendedOwner");

    function setUp() public {
        permissions = new JBPermissions(address(0));
        projects = new JBProjects(address(this), address(0), address(0));
    }

    function test_unmintedProjectOwnerCanBeHijackedByFirstMinter() external {
        vm.prank(deployer);
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), 1);

        assertEq(ownable.owner(), address(0), "owner should be unresolved before project 1 exists");

        vm.prank(attacker);
        uint256 hijackedProjectId = projects.createFor(attacker);

        assertEq(hijackedProjectId, 1, "attacker should receive the configured project ID");
        assertEq(ownable.owner(), attacker, "first minter becomes owner of the ownable contract");

        vm.prank(attacker);
        ownable.protectedMethod();

        vm.prank(intendedOwner);
        vm.expectRevert();
        ownable.protectedMethod();
    }
}
