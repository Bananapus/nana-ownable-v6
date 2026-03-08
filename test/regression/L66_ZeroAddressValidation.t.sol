// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockOwnable} from "../mocks/MockOwnable.sol";
import {JBOwnableOverrides} from "../../src/JBOwnableOverrides.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";

/// @title L66_ZeroAddressValidation
/// @notice Regression test for L-66: Verifies that deploying with a zero-address PROJECTS
///         contract and a non-zero projectId reverts at construction time, preventing
///         permanently broken project-based ownership.
contract L66_ZeroAddressValidation is Test {
    IJBProjects PROJECTS;
    IJBPermissions PERMISSIONS;

    address alice = makeAddr("alice");

    function setUp() public {
        PERMISSIONS = new JBPermissions(address(0));
        PROJECTS = new JBProjects(address(123), address(0), address(0));
    }

    /// @notice Deploying with projects=address(0) and non-zero projectId must revert.
    function test_zeroProjectsWithProjectId_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(JBOwnableOverrides.JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner.selector)
        );
        new MockOwnable(IJBProjects(address(0)), PERMISSIONS, address(0), uint88(1));
    }

    /// @notice Fuzz: any non-zero projectId with projects=address(0) must revert.
    function testFuzz_zeroProjectsWithAnyProjectId_reverts(uint88 projectId) public {
        vm.assume(projectId != 0);

        vm.expectRevert(
            abi.encodeWithSelector(JBOwnableOverrides.JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner.selector)
        );
        new MockOwnable(IJBProjects(address(0)), PERMISSIONS, address(0), projectId);
    }

    /// @notice Deploying with projects=address(0) and projectId=0 (address-based ownership)
    ///         should NOT revert for this error — it's valid as long as initialOwner != address(0).
    function test_zeroProjectsWithAddressOwnership_succeeds() public {
        // This is valid: address-based ownership with projects=address(0).
        MockOwnable ownable = new MockOwnable(IJBProjects(address(0)), PERMISSIONS, alice, uint88(0));
        assertEq(ownable.owner(), alice, "Owner should be alice with address-based ownership");
    }

    /// @notice Normal deployment with valid PROJECTS contract and projectId succeeds.
    function test_validProjectsWithProjectId_succeeds() public {
        uint256 projectId = PROJECTS.createFor(alice);
        MockOwnable ownable = new MockOwnable(PROJECTS, PERMISSIONS, address(0), uint88(projectId));
        assertEq(ownable.owner(), alice, "Owner should be alice via project NFT");
    }

    /// @notice The existing check for both zero owner and zero projectId is still enforced.
    function test_bothZero_stillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(JBOwnableOverrides.JBOwnableOverrides_InvalidNewOwner.selector));
        new MockOwnable(PROJECTS, PERMISSIONS, address(0), uint88(0));
    }
}
