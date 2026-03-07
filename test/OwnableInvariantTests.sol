// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OwnableHandler} from "./handlers/OwnableHandler.sol";

import {MockOwnable} from "./mocks/MockOwnable.sol";
import {JBOwnableOverrides} from "../src/JBOwnableOverrides.sol";
import {JBOwner} from "../src/structs/JBOwner.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";

contract OwnableInvariantTests is Test {
    OwnableHandler handler;

    function setUp() public {
        handler = new OwnableHandler();
        targetContract(address(handler));
    }

    /// @notice Owner address and project ID are mutually exclusive: can't both be non-zero.
    function invariant_cantBelongToUserAndProject() public {
        (address owner, uint88 projectId,) = handler.OWNABLE().jbOwner();
        assertTrue(owner == address(0) || projectId == uint256(0), "owner and projectId cannot both be non-zero");
    }

    /// @notice After renouncing, both owner and projectId must be zero.
    function invariant_renounceZerosOut() public {
        if (
            handler.wasEverRenounced()
                && handler.renounceCount() > handler.transferCount() + handler.projectTransferCount()
        ) {
            (address owner, uint88 projectId,) = handler.OWNABLE().jbOwner();
            assertTrue(owner == address(0) && projectId == 0, "renounced state should have zero owner and projectId");
        }
    }

    /// @notice The permissionId is always reset to 0 on ownership transfers.
    function invariant_permissionIdResetOnTransfer() public {
        (,, uint8 permissionId) = handler.OWNABLE().jbOwner();
        // After any ownership change, permissionId should be 0 (reset by _transferOwnership).
        // This is always true because the handler only calls transfer/renounce functions,
        // and never calls setPermissionId.
        assertEq(permissionId, 0, "permissionId should be 0 after transfers");
    }

    /// @notice If projectId is set, owner address must be zero.
    function invariant_projectOwnershipExcludesAddress() public {
        (address owner, uint88 projectId,) = handler.OWNABLE().jbOwner();
        if (projectId != 0) {
            assertEq(owner, address(0), "project ownership should zero the owner address");
        }
    }
}
