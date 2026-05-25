// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Describes who owns a `JBOwnable` contract and how they can delegate access.
/// @custom:member owner The owner address — only used when `projectId` is 0 (address-based ownership mode).
/// @custom:member projectId If non-zero, the holder of this Juicebox project's ERC-721 NFT is the owner. When set,
/// the `owner` field is ignored and ownership resolves dynamically via `JBProjects.ownerOf(projectId)`.
/// @custom:member permissionId The permission ID that delegates can hold via `JBPermissions`. Nonzero IDs only count
/// while the resolved owner matches the owner who last set the ID. Set to 0 to disable delegation entirely.
struct JBOwner {
    address owner;
    uint88 projectId;
    uint8 permissionId;
}
