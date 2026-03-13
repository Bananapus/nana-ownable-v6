// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockOwnable} from "./mocks/MockOwnable.sol";
import {JBOwnableOverrides} from "../src/JBOwnableOverrides.sol";
import {IJBOwnable} from "../src/interfaces/IJBOwnable.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";

/// @title OwnableEdgeCases
/// @notice Edge case and gap tests for JBOwnable: multi-hop NFT transfers,
///         project-to-project ownership, permissionId lifecycle, and nonexistent projects.
contract OwnableEdgeCases is Test {
    IJBProjects projects;
    IJBPermissions permissions;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address dave = makeAddr("dave");

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
    // Test 1: Multi-hop NFT transfer — ownership follows through A→B→C→D
    // =========================================================================
    function test_multiHopNFTTransfer_ownerFollows() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        assertEq(ownable.owner(), alice);

        // Transfer NFT: alice → bob
        vm.prank(alice);
        projects.transferFrom(alice, bob, projectId);
        assertEq(ownable.owner(), bob, "Should follow to bob");

        // Transfer NFT: bob → charlie
        vm.prank(bob);
        projects.transferFrom(bob, charlie, projectId);
        assertEq(ownable.owner(), charlie, "Should follow to charlie");

        // Transfer NFT: charlie → dave
        vm.prank(charlie);
        projects.transferFrom(charlie, dave, projectId);
        assertEq(ownable.owner(), dave, "Should follow to dave");

        // dave can call protectedMethod, alice/bob/charlie cannot
        vm.prank(dave);
        ownable.protectedMethod();

        vm.prank(alice);
        vm.expectRevert();
        ownable.protectedMethod();

        vm.prank(bob);
        vm.expectRevert();
        ownable.protectedMethod();

        vm.prank(charlie);
        vm.expectRevert();
        ownable.protectedMethod();
    }

    // =========================================================================
    // Test 2: Transfer project → different project
    // =========================================================================
    function test_transferProjectToProject() public {
        uint256 projectA = projects.createFor(alice);
        uint256 projectB = projects.createFor(bob);

        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectA));
        assertEq(ownable.owner(), alice);

        // Transfer ownership from project A to project B.
        vm.prank(alice);
        ownable.transferOwnershipToProject(projectB);

        // Owner should now be bob (owner of project B).
        assertEq(ownable.owner(), bob, "Owner should be projectB's owner (bob)");

        // alice no longer has access
        vm.prank(alice);
        vm.expectRevert();
        ownable.protectedMethod();

        // bob has access
        vm.prank(bob);
        ownable.protectedMethod();
    }

    // =========================================================================
    // Test 3: Full ownership cycle: address → project → address → project
    // =========================================================================
    function test_fullOwnershipCycle() public {
        uint256 projectA = projects.createFor(alice);
        uint256 projectB = projects.createFor(bob);

        // Start with address ownership.
        MockOwnable ownable = new MockOwnable(projects, permissions, charlie, 0);
        assertEq(ownable.owner(), charlie);

        // charlie → project A (alice)
        vm.prank(charlie);
        ownable.transferOwnershipToProject(projectA);
        assertEq(ownable.owner(), alice);

        // project A → bob (address)
        vm.prank(alice);
        ownable.transferOwnership(bob);
        assertEq(ownable.owner(), bob);

        // bob → project B (bob is also project B owner, but that's fine)
        vm.prank(bob);
        ownable.transferOwnershipToProject(projectB);
        assertEq(ownable.owner(), bob, "bob owns projectB so still bob");

        // Verify jbOwner struct is correct (projectId set, owner zeroed).
        (address storedOwner, uint88 storedProjectId, uint8 storedPermId) = ownable.jbOwner();
        assertEq(storedOwner, address(0), "owner field should be zero in project mode");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(storedProjectId, uint88(projectB), "projectId should be projectB");
        assertEq(storedPermId, 0, "permissionId should be 0");
    }

    // =========================================================================
    // Test 4: permissionId lifecycle through multiple transfers
    // =========================================================================
    function test_permissionIdLifecycle() public {
        uint256 projectA = projects.createFor(alice);

        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectA));

        // Set permissionId to 42.
        vm.prank(alice);
        ownable.setPermissionId(42);
        (,, uint8 permId) = ownable.jbOwner();
        assertEq(permId, 42);

        // Transfer to bob — permissionId should reset.
        vm.prank(alice);
        ownable.transferOwnership(bob);
        (,, permId) = ownable.jbOwner();
        assertEq(permId, 0, "permissionId should reset after transferOwnership");

        // Set permissionId again as new owner.
        vm.prank(bob);
        ownable.setPermissionId(99);
        (,, permId) = ownable.jbOwner();
        assertEq(permId, 99);

        // Transfer to project — permissionId should reset again.
        vm.prank(bob);
        ownable.transferOwnershipToProject(projectA);
        (,, permId) = ownable.jbOwner();
        assertEq(permId, 0, "permissionId should reset after transferOwnershipToProject");

        // Set permissionId as project owner.
        vm.prank(alice);
        ownable.setPermissionId(200);
        (,, permId) = ownable.jbOwner();
        assertEq(permId, 200);

        // Renounce — permissionId should be 0.
        vm.prank(alice);
        ownable.renounceOwnership();
        (,, permId) = ownable.jbOwner();
        assertEq(permId, 0, "permissionId should be 0 after renounce");
    }

    // =========================================================================
    // Test 5: Non-owner cannot call setPermissionId
    // =========================================================================
    function test_nonOwnerCannotSetPermissionId(address nonOwner) public {
        vm.assume(nonOwner != alice && nonOwner != address(0));

        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

        vm.prank(nonOwner);
        vm.expectRevert();
        ownable.setPermissionId(42);
    }

    // =========================================================================
    // Test 6: Transfer to nonexistent project reverts
    // =========================================================================
    function test_transferToNonexistentProject_reverts() public {
        // Create one project so count == 1.
        projects.createFor(alice);
        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

        // Project 2 doesn't exist.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(JBOwnableOverrides.JBOwnableOverrides_ProjectDoesNotExist.selector));
        ownable.transferOwnershipToProject(2);

        // Project 999 doesn't exist.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(JBOwnableOverrides.JBOwnableOverrides_ProjectDoesNotExist.selector));
        ownable.transferOwnershipToProject(999);
    }

    // =========================================================================
    // Test 7: Delegated access — permission granted on project, then NFT
    //         transferred, old delegate loses access
    // =========================================================================
    function test_delegatedAccess_lostAfterNFTTransfer() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // Set permissionId so delegation is possible.
        vm.prank(alice);
        ownable.setPermissionId(42);

        // Alice grants charlie permission 42 on the project.
        uint8[] memory permIds = new uint8[](1);
        permIds[0] = 42;
        vm.prank(alice);
        permissions.setPermissionsFor(
            // forge-lint: disable-next-line(unsafe-typecast)
            alice,
            JBPermissionsData({operator: charlie, projectId: uint56(projectId), permissionIds: permIds})
        );

        // Charlie can call protectedMethod (delegated via permissions).
        vm.prank(charlie);
        ownable.protectedMethod();

        // Transfer NFT to bob.
        vm.prank(alice);
        projects.transferFrom(alice, bob, projectId);

        // Charlie's delegation was from alice. Now owner is bob.
        // Charlie should lose access because _checkOwner resolves to bob,
        // and charlie has no permissions from bob.
        vm.prank(charlie);
        vm.expectRevert();
        ownable.protectedMethod();

        // bob can still call directly.
        vm.prank(bob);
        ownable.protectedMethod();
    }

    // =========================================================================
    // Test 8: OwnershipTransferred event emitted correctly
    // =========================================================================
    function test_ownershipTransferredEvent() public {
        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

        // Transfer to bob — expect event.
        vm.expectEmit(true, true, false, true);
        emit IJBOwnable.OwnershipTransferred(alice, bob, alice);

        vm.prank(alice);
        ownable.transferOwnership(bob);
    }

    // =========================================================================
    // Test 9: PermissionIdChanged event emitted correctly
    // =========================================================================
    function test_permissionIdChangedEvent() public {
        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

        vm.expectEmit(true, true, false, true);
        emit IJBOwnable.PermissionIdChanged(42, alice);

        vm.prank(alice);
        ownable.setPermissionId(42);
    }

    // =========================================================================
    // Test 10: Fuzz — transfer to any valid project, verify owner resolution
    // =========================================================================
    function testFuzz_transferToProject(address projectOwner) public isNotContract(projectOwner) {
        vm.assume(projectOwner != address(0));

        uint256 projectId = projects.createFor(projectOwner);
        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

        vm.prank(alice);
        ownable.transferOwnershipToProject(projectId);

        assertEq(ownable.owner(), projectOwner, "Owner should match project owner");

        // Verify jbOwner struct.
        (address storedOwner, uint88 storedProjectId,) = ownable.jbOwner();
        assertEq(storedOwner, address(0), "stored owner should be zero");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(storedProjectId, uint88(projectId), "stored projectId should match");
    }

    // =========================================================================
    // Test 11: Renounced contract cannot reclaim ownership
    // =========================================================================
    /// @notice After renouncing, no one can call transferOwnership, transferOwnershipToProject,
    ///         setPermissionId, or renounceOwnership again.
    function test_renouncedContract_cannotReclaim() public {
        uint256 projectId = projects.createFor(alice);
        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

        vm.prank(alice);
        ownable.renounceOwnership();

        // Nobody can transfer ownership back.
        vm.prank(alice);
        vm.expectRevert();
        ownable.transferOwnership(alice);

        vm.prank(bob);
        vm.expectRevert();
        ownable.transferOwnership(bob);

        // Nobody can transfer to a project.
        vm.prank(alice);
        vm.expectRevert();
        ownable.transferOwnershipToProject(projectId);

        // Nobody can set permissionId.
        vm.prank(alice);
        vm.expectRevert();
        ownable.setPermissionId(1);

        // Nobody can renounce again (already renounced, _checkOwner fails).
        vm.prank(alice);
        vm.expectRevert();
        ownable.renounceOwnership();
    }

    // =========================================================================
    // Test 12: _msgSender is NOT ERC2771-aware (design documentation)
    // =========================================================================
    /// @notice JBOwnable uses plain Context._msgSender() (returns msg.sender),
    ///         NOT ERC2771Context. This test documents that a trusted forwarder
    ///         appending a sender address to calldata does NOT affect _checkOwner.
    function test_noERC2771_trustedForwarderHasNoEffect() public {
        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

        // Simulate what a trusted forwarder would do: call with alice's address
        // appended to calldata. Since JBOwnable uses plain Context, this has no effect.
        // The msg.sender is still bob, not alice.
        bytes memory callData = abi.encodeWithSelector(MockOwnable.protectedMethod.selector);
        bytes memory forwardedCallData = abi.encodePacked(callData, alice);

        vm.prank(bob);
        (bool success,) = address(ownable).call(forwardedCallData);
        assertFalse(success, "Forwarded call should fail - JBOwnable ignores appended sender");

        // Direct call from alice still works.
        vm.prank(alice);
        ownable.protectedMethod();
    }
}
