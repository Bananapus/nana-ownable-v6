# Ownable Runtime

## Core Roles

- [`src/JBOwnable.sol`](../src/JBOwnable.sol) is the concrete downstream inheritance surface.
- [`src/JBOwnableOverrides.sol`](../src/JBOwnableOverrides.sol) owns owner resolution and delegated permission checks.

## High-Risk Areas

- Effective-owner resolution: ownership may follow a project NFT rather than a fixed address.
- Delegated `onlyOwner` permissions: the chosen permission ID changes who can administer a contract.
- Transfer semantics: explicit ownable transfers reset permission IDs, while project NFT transfers preserve the stored
  ID and rely on `_permissionOwner` to decide whether it is effective.

## Tests To Trust First

- [`test/Ownable.t.sol`](../test/Ownable.t.sol) for baseline behavior.
- [`test/OwnableEdgeCases.t.sol`](../test/OwnableEdgeCases.t.sol) and [`test/OwnableAttacks.t.sol`](../test/OwnableAttacks.t.sol) for edge and adversarial cases.
- [`test/OwnableInvariantTests.sol`](../test/OwnableInvariantTests.sol) for broader invariants.
- [`test/regression/BurnLockProtection.t.sol`](../test/regression/BurnLockProtection.t.sol), [`test/RegressionUnmintedProjectHijack.t.sol`](../test/RegressionUnmintedProjectHijack.t.sol), [`test/regression/PermissionIdNFTTransfer.t.sol`](../test/regression/PermissionIdNFTTransfer.t.sol), and [`test/audit/CodexNemesisPermissionReactivation.t.sol`](../test/audit/CodexNemesisPermissionReactivation.t.sol) for the regressions most likely to matter in review.
