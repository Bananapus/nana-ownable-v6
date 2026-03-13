// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockOwnable} from "./mocks/MockOwnable.sol";
import {JBOwnableOverrides} from "../src/JBOwnableOverrides.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";

/// @title OwnableAttacks
/// @notice Adversarial security tests for JBOwnable covering edge cases
///         around dual ownership, permission semantics, and renounced contracts.
contract OwnableAttacks is Test {
    IJBProjects projects;
    IJBPermissions permissions;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    modifier isNotContract(address a) {
        uint256 size;
        assembly {
            size := extcodesize(a)
        }
        vm.assume(size == 0);
        _;
    }

    function setUp() public {
        permissions = new JBPermissions(address(0));
        projects = new JBProjects(address(123), address(0), address(0));
    }

    // =========================================================================
    // Test 1: Constructor rejects both owner AND projectId set
    // =========================================================================
    function test_bothOwnerAndProjectId_constructorReverts() public {
        uint256 projectId = projects.createFor(alice);

        vm.expectRevert(abi.encodeWithSelector(JBOwnableOverrides.JBOwnableOverrides_InvalidNewOwner.selector));
        // forge-lint: disable-next-line(unsafe-typecast)
        new MockOwnable(projects, permissions, bob, uint88(projectId));
    }

    // =========================================================================
    // Test 2: Renounced contract — protectedMethod always reverts
    // =========================================================================
    function test_renounced_protectedMethodAlwaysReverts() public {
        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

        // Owner can call.
        vm.prank(alice);
        ownable.protectedMethod();

        // Renounce.
        vm.prank(alice);
        ownable.renounceOwnership();
        assertEq(ownable.owner(), address(0), "Should be renounced");

        // Now NOBODY can call — not alice, not bob, not anyone.
        vm.prank(alice);
        vm.expectRevert();
        ownable.protectedMethod();

        vm.prank(bob);
        vm.expectRevert();
        ownable.protectedMethod();

        vm.prank(attacker);
        vm.expectRevert();
        ownable.protectedMethod();
    }

    // =========================================================================
    // Test 3: Permission ID reset on transfer
    // =========================================================================
    /// @notice After any ownership transfer, permissionId should reset to 0.
    ///         This prevents stale permission delegation.
    function test_permissionIdResetOnTransfer() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // Set permission ID.
        vm.prank(alice);
        ownable.setPermissionId(42);

        (, uint88 pid, uint8 permId) = ownable.jbOwner();
        assertEq(permId, 42, "Permission ID should be 42");

        // Transfer to bob directly.
        vm.prank(alice);
        ownable.transferOwnership(bob);

        (, pid, permId) = ownable.jbOwner();
        assertEq(permId, 0, "Permission ID should reset to 0 after transfer");
    }

    // =========================================================================
    // Test 4: Stale owner after NFT transfer
    // =========================================================================
    /// @notice After transferring project NFT, old owner should lose access.
    function test_staleOwner_afterNFTTransfer() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // Alice is current owner.
        assertEq(ownable.owner(), alice);
        vm.prank(alice);
        ownable.protectedMethod(); // Should succeed.

        // Transfer project NFT to bob.
        vm.prank(alice);
        projects.transferFrom(alice, bob, projectId);

        // Alice should no longer be owner.
        assertEq(ownable.owner(), bob, "Bob should be new owner");

        // Alice cannot call protectedMethod anymore.
        vm.prank(alice);
        vm.expectRevert();
        ownable.protectedMethod();

        // Bob can call.
        vm.prank(bob);
        ownable.protectedMethod();
    }

    // =========================================================================
    // Test 5: Transfer to project with overflow ID — must revert
    // =========================================================================
    /// @notice transferOwnershipToProject with projectId > type(uint88).max should revert.
    function test_transferOwnershipToProject_overflowReverts() public {
        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

        // type(uint88).max + 1 = 309485009821345068724781056
        uint256 overflowId = uint256(type(uint88).max) + 1;

        vm.prank(alice);
        vm.expectRevert();
        ownable.transferOwnershipToProject(overflowId);
    }

    // =========================================================================
    // Test 6: ROOT permission on wrong project doesn't grant access
    // =========================================================================
    /// @notice Attacker has ROOT permission on their own project. Verify it
    ///         doesn't grant access to a different project's JBOwnable.
    function test_rootOnWrongProject_noAccess() public {
        // Create two projects.
        uint256 aliceProject = projects.createFor(alice);
        uint256 attackerProject = projects.createFor(attacker);

        // Ownable is owned by alice's project.
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(aliceProject));

        // Set permission ID so delegated access is possible.
        vm.prank(alice);
        ownable.setPermissionId(42);

        // Attacker grants themselves ROOT (permission 1) on their OWN project.
        uint8[] memory rootPerms = new uint8[](1);
        rootPerms[0] = 1; // ROOT

        vm.prank(attacker);
        permissions.setPermissionsFor(
            attacker,
            // forge-lint: disable-next-line(unsafe-typecast)
            JBPermissionsData({operator: attacker, projectId: uint56(attackerProject), permissionIds: rootPerms})
        );

        // Attacker tries to call protectedMethod — should still fail because
        // ROOT is on attackerProject, not aliceProject.
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector, alice, attacker, aliceProject, 42
            )
        );
        ownable.protectedMethod();
    }
}
