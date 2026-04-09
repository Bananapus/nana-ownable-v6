# Ownable Runtime

## Core Roles

- [`src/JBOwnable.sol`](../src/JBOwnable.sol) is the concrete downstream inheritance surface.
- [`src/JBOwnableOverrides.sol`](../src/JBOwnableOverrides.sol) owns owner resolution and delegated permission checks.

## High-Risk Areas

- Effective-owner resolution: ownership may follow a project NFT rather than a fixed address.
- Delegated `onlyOwner` permissions: the chosen permission ID changes who can administer a contract.
- Transfer semantics: permission IDs reset on transfer, which is safer but easy to forget.

## Tests To Trust First

- [`test/Ownable.t.sol`](../test/Ownable.t.sol) for baseline behavior.
- [`test/OwnableEdgeCases.t.sol`](../test/OwnableEdgeCases.t.sol) and [`test/OwnableAttacks.t.sol`](../test/OwnableAttacks.t.sol) for edge and adversarial cases.
- [`test/OwnableInvariantTests.sol`](../test/OwnableInvariantTests.sol) for broader invariants.
