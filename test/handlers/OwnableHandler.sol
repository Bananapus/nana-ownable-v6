// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// import { Test } from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {MockOwnable} from "../mocks/MockOwnable.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";

contract OwnableHandler is CommonBase, StdCheats, StdUtils {
    IJBProjects public immutable PROJECTS;
    IJBPermissions public immutable PERMISSIONS;
    MockOwnable public immutable OWNABLE;

    address[] public actors;
    address internal currentActor;

    // Ghost variables for tracking state.
    uint256 public transferCount;
    uint256 public renounceCount;
    uint256 public projectTransferCount;
    bool public wasEverRenounced;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor() {
        address deployer = vm.addr(1);
        address initialOwner = vm.addr(2);
        // Deploy the permissions contract.
        PERMISSIONS = new JBPermissions(address(0));
        // Deploy the `JBProjects` contract.
        PROJECTS = new JBProjects(address(123), address(0), address(0));
        // Deploy the `JBOwnable` contract.
        vm.prank(deployer);
        OWNABLE = new MockOwnable(PROJECTS, PERMISSIONS, initialOwner, uint88(0));

        actors.push(deployer);
        actors.push(initialOwner);
        actors.push(address(420));
    }

    function transferOwnershipToAddress(uint256 actorIndexSeed, address _newOwner) public useActor(actorIndexSeed) {
        // Skip zero address — that's renounceOwnership's job.
        if (_newOwner == address(0)) return;

        try OWNABLE.transferOwnership(_newOwner) {
            transferCount++;
        } catch {}
    }

    function renounceOwnership(uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        try OWNABLE.renounceOwnership() {
            renounceCount++;
            wasEverRenounced = true;
        } catch {}
    }

    function transferOwnershipToProject(uint256 actorIndexSeed, uint256 projectId) public useActor(actorIndexSeed) {
        // Bound to valid project ID range (1 to type(uint88).max).
        projectId = bound(projectId, 1, type(uint88).max);

        try OWNABLE.transferOwnershipToProject(projectId) {
            projectTransferCount++;
        } catch {}
    }
}
