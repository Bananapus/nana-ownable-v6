# Changelog

## Scope

This file describes the verified change from `nana-ownable-v5` to the current `nana-ownable-v6` repo.

## Current v6 surface

- `JBOwnable`
- `JBOwnableOverrides`
- `IJBOwnable`
- `JBOwner`

## Summary

- Project-backed ownership resolves through a single internal `_projectOwnerOf` helper, so the `PROJECTS.ownerOf` try-catch lives in one place and every contract inheriting `JBOwnable` carries less bytecode.
- Project-backed ownership tolerates invalid or burned project NFTs: an `ownerOf` failure resolves to `address(0)` rather than surfacing as an unchecked revert.
- The project-ownership transfer path validates that the target project exists before transferring control to it.
- Ownership-transfer events carry the caller through `_msgSender()`, so meta-transaction relayers report the originating account.
- The implementation baseline is `0.8.28`.

## Maintenance

- Raise dependency floors to the latest published versions; document NatSpec, comment, and lint conventions in `STYLE_GUIDE.md`.

## Verified deltas

- `JBOwnable` emits ownership-transfer events through `_msgSender()`.
- `transferOwnershipToProject(...)` reverts `JBOwnableOverrides_ProjectDoesNotExist` when the target project does not exist.
- Project-owner resolution falls back to `address(0)` when `PROJECTS.ownerOf` reverts, rather than bubbling the revert to the caller.
- Imports resolve against `@bananapus/core-v6`.

## Breaking ABI changes

- `IJBOwnable` preserves its public function shape; there is no function-signature migration.
- The migration is behavioral: project-backed ownership resolution and transfer validation are stricter.

## Indexer impact

- Event names are stable, but `OwnershipTransferred.caller` carries the `_msgSender()` account rather than the raw transaction sender, so meta-transaction-aware consumers should read the caller field as the originating account.

## Migration notes

- Consumers that relied on `owner()` reverting for an invalid project-backed state must instead handle a resolved `address(0)`.
- Rebuild imports against `@bananapus/core-v6`.
