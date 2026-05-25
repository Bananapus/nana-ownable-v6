// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockOwnable} from "../mocks/MockOwnable.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title BurnLockProtection
/// @notice Verifies that if project ownership becomes unreadable, `owner()` returns address(0) and `_checkOwner()`
/// reverts gracefully instead of bubbling the upstream `ownerOf` revert.
contract BurnLockProtection is Test {
    IJBProjects projects;
    IJBPermissions permissions;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        permissions = new JBPermissions(address(0));
        projects = new JBProjects(address(123), address(0), address(0));
    }

    /// @notice When `ownerOf` reverts, `owner()` returns address(0) instead of reverting.
    function test_burnedProjectNFT_ownerReturnsZero() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // Verify normal operation before making project ownership unreadable.
        assertEq(ownable.owner(), alice, "Owner should be alice before ownerOf reverts");

        // Make `ownerOf` revert for this project ID.
        vm.mockCallRevert(
            address(projects), abi.encodeWithSelector(IERC721.ownerOf.selector, projectId), "ERC721: invalid token ID"
        );

        // Unreadable project ownership fails closed to address(0).
        address resolvedOwner = ownable.owner();
        assertEq(resolvedOwner, address(0), "owner() should return address(0) when ownerOf reverts");
    }

    /// @notice When `ownerOf` reverts, `_checkOwner()` should revert with the standard unauthorized error.
    function test_burnedProjectNFT_checkOwnerRevertsGracefully() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        // Alice can call the protected method while project ownership is readable.
        vm.prank(alice);
        ownable.protectedMethod();

        // Make project ownership unreadable.
        vm.mockCallRevert(
            address(projects), abi.encodeWithSelector(IERC721.ownerOf.selector, projectId), "ERC721: invalid token ID"
        );

        // Nobody can call protected methods, and the revert comes from the ownable permission check.
        vm.prank(alice);
        vm.expectRevert();
        ownable.protectedMethod();

        vm.prank(bob);
        vm.expectRevert();
        ownable.protectedMethod();
    }

    /// @notice Address-based ownership is unaffected by unreadable project ownership.
    function test_addressBasedOwnership_unaffectedByTryCatch() public {
        MockOwnable ownable = new MockOwnable(projects, permissions, alice, 0);

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

    /// @notice Normal project-based ownership still works while `ownerOf` is readable.
    function test_normalProjectOwnership_stillWorks() public {
        uint256 projectId = projects.createFor(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        MockOwnable ownable = new MockOwnable(projects, permissions, address(0), uint88(projectId));

        assertEq(ownable.owner(), alice);

        // Transfer project NFT.
        vm.prank(alice);
        projects.transferFrom(alice, bob, projectId);

        assertEq(ownable.owner(), bob, "Owner should follow project NFT transfer");

        vm.prank(bob);
        ownable.protectedMethod();
    }
}
