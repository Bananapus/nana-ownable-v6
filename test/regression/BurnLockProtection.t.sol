// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockOwnable} from "../mocks/MockOwnable.sol";
import {JBOwnableOverrides} from "../../src/JBOwnableOverrides.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title BurnLockProtection
/// @notice Verifies that if a project NFT is burned/invalidated,
///         owner() returns address(0) and _checkOwner() reverts gracefully instead of
///         permanently locking the contract with an unrecoverable revert.
contract BurnLockProtection is Test {
    IJBProjects PROJECTS;
    IJBPermissions PERMISSIONS;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        PERMISSIONS = new JBPermissions(address(0));
        PROJECTS = new JBProjects(address(123), address(0), address(0));
    }

    /// @notice When a project NFT is burned (simulated via mockCallRevert), owner() should
    ///         return address(0) instead of reverting — contract degrades to "renounced" state.
    function test_burnedProjectNFT_ownerReturnsZero() public {
        uint256 projectId = PROJECTS.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(PROJECTS, PERMISSIONS, address(0), uint88(projectId));

        // Verify normal operation first.
        assertEq(ownable.owner(), alice, "Owner should be alice before burn");

        // Simulate project NFT burn by making ownerOf revert for this projectId.
        vm.mockCallRevert(
            address(PROJECTS), abi.encodeWithSelector(IERC721.ownerOf.selector, projectId), "ERC721: invalid token ID"
        );

        // After burn, owner() should return address(0) — NOT revert.
        address resolvedOwner = ownable.owner();
        assertEq(resolvedOwner, address(0), "owner() should return address(0) when project NFT is burned");
    }

    /// @notice When a project NFT is burned, _checkOwner() should revert with the standard
    ///         Unauthorized error (not an unrecoverable ownerOf revert), making the contract
    ///         behave as if ownership was renounced.
    function test_burnedProjectNFT_checkOwnerRevertsGracefully() public {
        uint256 projectId = PROJECTS.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(PROJECTS, PERMISSIONS, address(0), uint88(projectId));

        // Alice can call the protected method before burn.
        vm.prank(alice);
        ownable.protectedMethod();

        // Simulate project NFT burn.
        vm.mockCallRevert(
            address(PROJECTS), abi.encodeWithSelector(IERC721.ownerOf.selector, projectId), "ERC721: invalid token ID"
        );

        // After burn, nobody can call protected methods — but the revert is graceful
        // (Unauthorized from _requirePermissionFrom, not a raw ownerOf revert).
        vm.prank(alice);
        vm.expectRevert();
        ownable.protectedMethod();

        vm.prank(bob);
        vm.expectRevert();
        ownable.protectedMethod();
    }

    /// @notice Address-based ownership is unaffected by the try-catch change.
    function test_addressBasedOwnership_unaffectedByTryCatch() public {
        MockOwnable ownable = new MockOwnable(PROJECTS, PERMISSIONS, alice, 0);

        assertEq(ownable.owner(), alice, "Owner should be alice");

        vm.prank(alice);
        ownable.protectedMethod();

        // Transfer to bob.
        vm.prank(alice);
        ownable.transferOwnership(bob);
        assertEq(ownable.owner(), bob, "Owner should be bob after transfer");

        vm.prank(bob);
        ownable.protectedMethod();
    }

    /// @notice Normal project-based ownership still works correctly after the fix.
    function test_normalProjectOwnership_stillWorks() public {
        uint256 projectId = PROJECTS.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(PROJECTS, PERMISSIONS, address(0), uint88(projectId));

        assertEq(ownable.owner(), alice);

        // Transfer project NFT.
        vm.prank(alice);
        PROJECTS.transferFrom(alice, bob, projectId);

        assertEq(ownable.owner(), bob, "Owner should follow project NFT transfer");

        vm.prank(bob);
        ownable.protectedMethod();
    }
}
