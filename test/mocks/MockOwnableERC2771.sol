// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {JBOwnable} from "../../src/JBOwnable.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";

/// @notice Mock that overrides _msgSender() to simulate ERC-2771 meta-transaction behavior.
/// @dev When called by the trusted forwarder, the last 20 bytes of calldata are treated as the real sender.
contract MockOwnableERC2771 is JBOwnable {
    event ProtectedMethodCalled();

    address public immutable TRUSTED_FORWARDER;

    constructor(
        IJBProjects projects,
        IJBPermissions permissions,
        address initialOwner,
        uint88 initialProjectIdOwner,
        address trustedForwarder
    )
        JBOwnable(permissions, projects, initialOwner, initialProjectIdOwner)
    {
        TRUSTED_FORWARDER = trustedForwarder;
    }

    function protectedMethod() external onlyOwner {
        emit ProtectedMethodCalled();
    }

    function _msgSender() internal view override returns (address) {
        if (msg.sender == TRUSTED_FORWARDER && msg.data.length >= 20) {
            return address(bytes20(msg.data[msg.data.length - 20:]));
        }
        return msg.sender;
    }
}
