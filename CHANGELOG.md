# Changelog

## Unreleased

- Resolve a project's owner through a single internal `_projectOwnerOf` helper so the `PROJECTS.ownerOf` try-catch lives in one place instead of at every call site, reducing the bytecode every contract that inherits `JBOwnable` carries. Behavior is unchanged.
- Raise dependency floors to the latest published versions.
- Document NatSpec, comment, and lint conventions in STYLE_GUIDE.

## Scope

This file describes the verified change from `nana-ownable-v5` to the current `nana-ownable-v6` repo.

## Current v6 surface

- `JBOwnable`
- `JBOwnableOverrides`
- `IJBOwnable`
- `JBOwner`

## Summary

- Project-backed ownership is more defensive than in v5. The current implementation tolerates invalid or burned project NFTs by handling `ownerOf` failures instead of surfacing them as unchecked behavior.
- The project-ownership path validates its inputs more strictly before transferring control to a project.
- The implementation files now compile on the v6 `0.8.28` baseline instead of the old floating `^0.8.23` setup.

## Verified deltas

- `JBOwnable` now emits ownership-transfer events through `_msgSender()` instead of raw `msg.sender`.
- The transfer-event path is explicitly documented to revert when the new project does not exist, instead of silently tolerating a bad target.
- The current imports point at `core-v6`, not `core-v5`.

## Breaking ABI changes

- There is no meaningful public function migration in `IJBOwnable`; the interface mostly preserved its shape.
- The important migration is behavioral: project-backed ownership resolution and transfer validation are stricter.

## Indexer impact

- Event names are stable, but the `caller` field is now emitted through `_msgSender()` semantics in the implementation.
- Meta-transaction-aware consumers should prefer the v6 behavior over raw-`msg.sender` assumptions.

## Migration notes

- If you depended on `owner()` reverting for invalid project-backed ownership states, revisit that expectation.
- Rebuild imports against the v6 core package and the current ownable contracts. This repo is small, but the behavior is intentionally stricter than v5.
