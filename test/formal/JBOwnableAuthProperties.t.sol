// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";

import {JBOwnable} from "../../src/JBOwnable.sol";
import {JBOwnableOverrides} from "../../src/JBOwnableOverrides.sol";
import {JBOwner} from "../../src/structs/JBOwner.sol";

/// @title JBOwnableAuthProperties
/// @notice Functional-correctness proofs for `JBOwnable`'s owner-RESOLUTION and AUTHORIZATION surface — the parts of
///         the spec (INVARIANTS.md sections A.1, A.2, A.3, D.1, D.5, D.6) that the existing `JBOwnableHalmos` suite
///         (which covers only the transfer/renounce state machine) does not machine-check.
/// @dev Each property is dual-implemented: `check_` for Halmos (symbolic) and `testFuzz_` for forge, matching the
///      house convention in `nana-core-v6/test/formal/FeeProperties.t.sol`. The pure struct-packing properties are
///      Halmos-only/`pure` because they have no state. The resolution/auth properties drive a real `JBOwnableHarness`
///      against minimal mocks so both engines exercise the actual `owner()` / `_checkOwner` code paths.

// =============================================================================
// Minimal mocks — kept tiny so the symbolic engine does not branch on the real
// JBProjects ERC-721 / JBPermissions storage machinery.
// =============================================================================

/// @notice Permissions mock whose verdict is fully controllable so auth-path proofs can pin "grant" vs "deny".
contract AuthPermissions {
    bool public verdict;

    function setVerdict(bool v) external {
        verdict = v;
    }

    function hasPermission(
        address,
        address,
        uint256,
        uint256,
        bool,
        bool
    )
        external
        view
        returns (bool)
    {
        return verdict;
    }

    // The override used by `_requirePermissionFrom` is the single-permission form; provide both shapes.
    function hasPermissions(
        address,
        address,
        uint256,
        uint256[] calldata,
        bool,
        bool
    )
        external
        view
        returns (bool)
    {
        return verdict;
    }
}

/// @notice Project NFT mock that reverts on unset tokens, matching ERC-721 `ownerOf` semantics.
contract AuthProjects {
    mapping(uint256 => address) internal _ownerOf;
    uint256 public count;

    function setOwner(uint256 projectId, address owner) external {
        _ownerOf[projectId] = owner;
        if (projectId > count) count = projectId;
    }

    /// @notice Grow `count` without minting any specific token, to exercise the count-boundary check.
    function setCount(uint256 newCount) external {
        count = newCount;
    }

    function ownerOf(uint256 projectId) external view returns (address owner) {
        owner = _ownerOf[projectId];
        if (owner == address(0)) revert();
    }
}

/// @notice Concrete `JBOwnable` exposing the internal auth/resolution helpers for proofs.
contract JBOwnableHarness is JBOwnable {
    constructor(
        IJBPermissions permissions,
        IJBProjects projects,
        address initialOwner,
        uint88 initialProjectIdOwner
    )
        JBOwnable(permissions, projects, initialOwner, initialProjectIdOwner)
    {}

    /// @notice A function gated by `onlyOwner`; reverts iff `_checkOwner` reverts.
    function gated() external view onlyOwner {}

    function exposedPermissionOwner() external view returns (address) {
        return _permissionOwner;
    }

    function exposedTransferOwnership(address newOwner, uint88 projectId) external {
        _transferOwnership({newOwner: newOwner, projectId: projectId});
    }

    function exposedSetPermissionId(uint8 permissionId) external {
        _setPermissionId(permissionId);
    }
}

contract JBOwnableAuthProperties is Test {
    // =========================================================================
    // Property 1 (PURE): JBOwner struct field isolation / single-slot packing
    //   Packing (owner, projectId, permissionId) and reading back must return
    //   exactly the inputs — no field bleeds into another. Load-bearing because
    //   one SLOAD feeds every _checkOwner.
    // =========================================================================
    function check_jbOwnerFieldIsolation(address owner, uint88 projectId, uint8 permissionId) public pure {
        JBOwner memory o = JBOwner({owner: owner, projectId: projectId, permissionId: permissionId});
        assert(o.owner == owner);
        assert(o.projectId == projectId);
        assert(o.permissionId == permissionId);
        // Mutating one field leaves the others untouched.
        o.permissionId = 0;
        assert(o.owner == owner);
        assert(o.projectId == projectId);
        assert(o.permissionId == 0);
    }

    function testFuzz_jbOwnerFieldIsolation(address owner, uint88 projectId, uint8 permissionId) public {
        JBOwner memory o = JBOwner({owner: owner, projectId: projectId, permissionId: permissionId});
        assertEq(o.owner, owner);
        assertEq(o.projectId, projectId);
        assertEq(o.permissionId, permissionId);
        o.permissionId = 0;
        assertEq(o.owner, owner);
        assertEq(o.projectId, projectId);
    }

    // =========================================================================
    // Helper: build a fresh address-owned harness (the cheapest mode).
    // =========================================================================
    function _newAddressOwned(address initialOwner) internal returns (JBOwnableHarness h, AuthProjects p) {
        vm.assume(initialOwner != address(0));
        p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        h = new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), initialOwner, 0);
    }

    // =========================================================================
    // Property 2 (STATE): owner() in address mode == stored owner exactly.
    //   Spec A.1.4 / D.4 — address mode never consults the project NFT.
    // =========================================================================
    function check_ownerAddressModeIsStored(address initialOwner) public {
        (JBOwnableHarness h,) = _newAddressOwned(initialOwner);
        assert(h.owner() == initialOwner);
        (address stored, uint88 pid,) = h.jbOwner();
        assert(stored == initialOwner);
        assert(pid == 0);
    }

    function testFuzz_ownerAddressModeIsStored(address initialOwner) public {
        (JBOwnableHarness h,) = _newAddressOwned(initialOwner);
        assertEq(h.owner(), initialOwner);
    }

    // =========================================================================
    // Property 3 (STATE): owner() in project mode resolves the live NFT holder,
    //   and fails CLOSED to address(0) when the project is unreadable.
    //   Spec A.1.2 + A.1.3 + D.1.
    // =========================================================================
    function check_ownerProjectModeResolvesAndFailsClosed(uint88 projectId, address nftHolder) public {
        vm.assume(projectId != 0);
        vm.assume(nftHolder != address(0));

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        // Pre-bind project mode at construction (allowed even before mint).
        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), address(0), projectId);

        // Unminted project: owner() must fail closed to address(0).
        assert(h.owner() == address(0));

        // Mint: owner() now tracks the holder dynamically.
        p.setOwner(projectId, nftHolder);
        assert(h.owner() == nftHolder);
    }

    function testFuzz_ownerProjectModeResolvesAndFailsClosed(uint88 projectId, address nftHolder) public {
        vm.assume(projectId != 0);
        vm.assume(nftHolder != address(0));

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), address(0), projectId);

        assertEq(h.owner(), address(0), "unminted project must resolve to zero");
        p.setOwner(projectId, nftHolder);
        assertEq(h.owner(), nftHolder, "minted project must resolve to NFT holder");
    }

    // =========================================================================
    // Property 4 (STATE): address-mode onlyOwner is direct-owner-only and never
    //   consults JBPermissions. Even with the permissions mock returning TRUE
    //   for everyone, a non-owner caller must revert. Spec A.2.1, A.2.5, D.6.
    // =========================================================================
    function check_addressModeOnlyOwnerIgnoresPermissions(address initialOwner, address caller) public {
        vm.assume(initialOwner != address(0));
        vm.assume(caller != initialOwner);

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        perm.setVerdict(true); // grant everyone everything in the permission system

        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), initialOwner, 0);

        // Owner passes.
        vm.prank(initialOwner);
        h.gated();

        // Non-owner reverts despite the all-yes permission system (address mode never queries it).
        vm.prank(caller);
        try h.gated() {
            assert(false);
        } catch {
            assert(true);
        }
    }

    function testFuzz_addressModeOnlyOwnerIgnoresPermissions(address initialOwner, address caller) public {
        vm.assume(initialOwner != address(0));
        vm.assume(caller != initialOwner);

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        perm.setVerdict(true);

        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), initialOwner, 0);

        vm.prank(initialOwner);
        h.gated();

        vm.prank(caller);
        vm.expectRevert();
        h.gated();
    }

    // =========================================================================
    // Property 5 (STATE): address-mode setPermissionId(nonzero) reverts;
    //   setPermissionId(0) is a no-op accepted. Spec A.2.2, B.1.4.
    // =========================================================================
    function check_addressModeRejectsNonzeroPermissionId(address initialOwner, uint8 permissionId) public {
        (JBOwnableHarness h,) = _newAddressOwned(initialOwner);

        vm.startPrank(initialOwner);
        if (permissionId == 0) {
            h.setPermissionId(0); // allowed
            (,, uint8 pid) = h.jbOwner();
            assert(pid == 0);
        } else {
            try h.setPermissionId(permissionId) {
                assert(false);
            } catch {
                assert(true);
            }
        }
        vm.stopPrank();
    }

    function testFuzz_addressModeRejectsNonzeroPermissionId(address initialOwner, uint8 permissionId) public {
        (JBOwnableHarness h,) = _newAddressOwned(initialOwner);
        vm.startPrank(initialOwner);
        if (permissionId == 0) {
            h.setPermissionId(0);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    JBOwnableOverrides.JBOwnableOverrides_AddressOwnerCannotSetPermissionId.selector,
                    initialOwner,
                    permissionId
                )
            );
            h.setPermissionId(permissionId);
        }
        vm.stopPrank();
    }

    // =========================================================================
    // Property 6 (STATE): project-mode setPermissionId stores the ID AND
    //   snapshots the CURRENT resolved owner into _permissionOwner.
    //   Spec A.2.3, D.7.
    // =========================================================================
    function check_setPermissionIdSnapshotsResolvedOwner(
        uint88 projectId,
        address nftHolder,
        uint8 permissionId
    )
        public
    {
        vm.assume(projectId != 0);
        vm.assume(nftHolder != address(0));
        vm.assume(permissionId != 0);

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        p.setOwner(projectId, nftHolder);
        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), address(0), projectId);

        vm.prank(nftHolder);
        h.setPermissionId(permissionId);

        (,, uint8 storedPid) = h.jbOwner();
        assert(storedPid == permissionId);
        // _permissionOwner is the resolved owner at write time, not the caller per se (here identical).
        assert(h.exposedPermissionOwner() == nftHolder);
    }

    function testFuzz_setPermissionIdSnapshotsResolvedOwner(
        uint88 projectId,
        address nftHolder,
        uint8 permissionId
    )
        public
    {
        vm.assume(projectId != 0);
        vm.assume(nftHolder != address(0));
        vm.assume(permissionId != 0);

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        p.setOwner(projectId, nftHolder);
        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), address(0), projectId);

        vm.prank(nftHolder);
        h.setPermissionId(permissionId);

        (,, uint8 storedPid) = h.jbOwner();
        assertEq(storedPid, permissionId);
        assertEq(h.exposedPermissionOwner(), nftHolder);
    }

    // =========================================================================
    // Property 7 (STATE) — CROWN JEWEL: NFT transfer auto-disables delegation.
    //   A delegate who passes the permission check (verdict=true) under the
    //   ORIGINAL owner loses access the instant the NFT moves to a new holder,
    //   because resolvedOwner != _permissionOwner zeroes the effective ID and
    //   _checkOwner falls into the direct-equality branch. Spec A.3.1, D.2, D.6.
    // =========================================================================
    function check_nftTransferAutoDisablesDelegation(
        uint88 projectId,
        address originalHolder,
        address newHolder,
        address delegate,
        uint8 permissionId
    )
        public
    {
        vm.assume(projectId != 0);
        vm.assume(permissionId != 0);
        vm.assume(originalHolder != address(0) && newHolder != address(0) && delegate != address(0));
        vm.assume(originalHolder != newHolder);
        // The delegate is a third party, not the new holder (the interesting stale case).
        vm.assume(delegate != newHolder);

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        perm.setVerdict(true); // delegate would always pass _requirePermissionFrom

        p.setOwner(projectId, originalHolder);
        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), address(0), projectId);

        // Original holder enables delegation.
        vm.prank(originalHolder);
        h.setPermissionId(permissionId);

        // Delegate currently passes (permission verdict true, snapshot matches resolved owner).
        vm.prank(delegate);
        h.gated();

        // NFT moves to a new holder. Delegation snapshot no longer matches the resolved owner.
        p.setOwner(projectId, newHolder);

        // The delegate must now be rejected, even though the permission system still says "true",
        // because the effective permission ID is forced to 0 (stale) and _checkOwner uses direct equality.
        vm.prank(delegate);
        try h.gated() {
            assert(false);
        } catch {
            assert(true);
        }

        // The new holder, by contrast, passes via direct ownership.
        vm.prank(newHolder);
        h.gated();
    }

    function testFuzz_nftTransferAutoDisablesDelegation(
        uint88 projectId,
        address originalHolder,
        address newHolder,
        address delegate,
        uint8 permissionId
    )
        public
    {
        vm.assume(projectId != 0);
        vm.assume(permissionId != 0);
        vm.assume(originalHolder != address(0) && newHolder != address(0) && delegate != address(0));
        vm.assume(originalHolder != newHolder);
        vm.assume(delegate != newHolder);

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        perm.setVerdict(true);

        p.setOwner(projectId, originalHolder);
        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), address(0), projectId);

        vm.prank(originalHolder);
        h.setPermissionId(permissionId);

        vm.prank(delegate);
        h.gated();

        p.setOwner(projectId, newHolder);

        vm.prank(delegate);
        vm.expectRevert();
        h.gated();

        vm.prank(newHolder);
        h.gated();
    }

    // =========================================================================
    // Property 8 (STATE): renounced state locks everyone out. After renounce
    //   no caller — owner, delegate, or third party — can pass _checkOwner.
    //   Spec B.1.3, B.2.4, D.1.
    // =========================================================================
    function check_renouncedLocksEveryoneOut(address initialOwner, address caller) public {
        // address(0) cannot originate a transaction in normal EVM execution; the spec's "no one can
        // authenticate after renounce" (D.1) is predicated on _msgSender() never being address(0).
        vm.assume(caller != address(0));
        (JBOwnableHarness h,) = _newAddressOwned(initialOwner);

        vm.prank(initialOwner);
        h.renounceOwnership();

        assert(h.owner() == address(0));

        // The (former) owner is locked out.
        vm.prank(initialOwner);
        try h.gated() {
            assert(false);
        } catch {
            assert(true);
        }

        // Any other caller is locked out.
        vm.prank(caller);
        try h.gated() {
            assert(false);
        } catch {
            assert(true);
        }
    }

    function testFuzz_renouncedLocksEveryoneOut(address initialOwner, address caller) public {
        vm.assume(caller != address(0));
        (JBOwnableHarness h,) = _newAddressOwned(initialOwner);

        vm.prank(initialOwner);
        h.renounceOwnership();

        assertEq(h.owner(), address(0));

        vm.prank(initialOwner);
        vm.expectRevert();
        h.gated();

        vm.prank(caller);
        vm.expectRevert();
        h.gated();
    }

    // =========================================================================
    // Property 9 (STATE): transferOwnershipToProject count boundary (D.5/B.1.2).
    //   projectId == count succeeds (already minted); projectId == count+1
    //   reverts ProjectDoesNotExist. The public path can never pre-bind a
    //   future project ID.
    // =========================================================================
    function check_publicProjectTransferCountBoundary(address initialOwner, uint88 existingCount) public {
        vm.assume(initialOwner != address(0));
        vm.assume(existingCount != 0);
        vm.assume(existingCount < type(uint88).max); // leave room for count+1

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        p.setCount(existingCount);

        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), initialOwner, 0);

        // projectId == count is accepted (boundary inclusive).
        vm.prank(initialOwner);
        h.transferOwnershipToProject(existingCount);
        (, uint88 pid,) = h.jbOwner();
        assert(pid == existingCount);

        // Re-own by address so the owner (initialOwner) can authenticate again.
        // After the project transfer above, owner() resolves via the (unminted) NFT -> address(0),
        // so initialOwner can no longer authenticate. Build a fresh harness for the revert case.
        JBOwnableHarness h2 =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), initialOwner, 0);

        // projectId == count + 1 must revert (future project, not yet minted).
        vm.prank(initialOwner);
        try h2.transferOwnershipToProject(uint256(existingCount) + 1) {
            assert(false);
        } catch {
            assert(true);
        }
    }

    function testFuzz_publicProjectTransferCountBoundary(address initialOwner, uint88 existingCount) public {
        vm.assume(initialOwner != address(0));
        vm.assume(existingCount != 0);
        vm.assume(existingCount < type(uint88).max);

        AuthProjects p = new AuthProjects();
        AuthPermissions perm = new AuthPermissions();
        p.setCount(existingCount);

        JBOwnableHarness h =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), initialOwner, 0);

        vm.prank(initialOwner);
        h.transferOwnershipToProject(existingCount);
        (, uint88 pid,) = h.jbOwner();
        assertEq(pid, existingCount);

        JBOwnableHarness h2 =
            new JBOwnableHarness(IJBPermissions(address(perm)), IJBProjects(address(p)), initialOwner, 0);

        vm.prank(initialOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                JBOwnableOverrides.JBOwnableOverrides_ProjectDoesNotExist.selector,
                uint256(existingCount) + 1,
                uint256(existingCount)
            )
        );
        h2.transferOwnershipToProject(uint256(existingCount) + 1);
    }
}
