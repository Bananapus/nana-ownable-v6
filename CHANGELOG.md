# V5 to V6 Changelog

## Scope

This is a V5-to-V6 migration changelog, not a package release log or commit history. It compares `nana-ownable-v5` in `../../v5/evm` with the current `nana-ownable-v6` repo.

## Current V6 Surface

- `JBOwnable`
- `JBOwnableOverrides`
- `IJBOwnable`
- `JBOwner`

## Summary

- The public ownership interface is intentionally close to V5, but V6 is stricter and safer around project-owned contracts.
- `owner()` resolves project ownership more defensively when the referenced project cannot be read yet or no longer exists.
- Transfers to project ownership validate the target project and reset permission IDs to avoid stale delegate authority.
- The event surface remains familiar, but V6 emits ownership transfer information with safer resolution for future/pre-bound projects.

## ABI, Event, and Error Changes

- Function surface remains stable:
  - `PROJECTS()`
  - `jbOwner()`
  - `owner()`
  - `renounceOwnership()`
  - `setPermissionId(uint8)`
  - `transferOwnership(address)`
  - `transferOwnershipToProject(uint256)`
- Events remain:
  - `OwnershipTransferred`
  - `PermissionIdChanged`
- Added or migration-sensitive errors:
  - `JBOwnableOverrides_AddressOwnerCannotSetPermissionId`
  - `JBOwnableOverrides_InvalidNewOwner`
  - `JBOwnableOverrides_ProjectDoesNotExist`

## Machine-Checked ABI Coverage

Generated from Foundry `out/**/*.json` artifacts, filtered to this repo's own runtime source roots and excluding tests, scripts, and dependencies.

- V5 comparison package: `nana-ownable-v5`.
- Own-source ABI artifacts compared: V6 `3`, V5 `3`.
- Contract/interface coverage: `0` added, `0` removed, `2` shared names with ABI changes, `1` shared names ABI-identical.
- Shared-name ABI item deltas: `6` added, `4` removed, `0` modified.

Shared ABI artifacts with changes:
- `JBOwnable`: `3` added, `2` removed, `0` modified ABI items.
- `JBOwnableOverrides`: `3` added, `2` removed, `0` modified ABI items.

Generated event/error name deltas:
- Error names added:
  - `JBOwnableOverrides_AddressOwnerCannotSetPermissionId`, `JBOwnableOverrides_InvalidNewOwner`, `JBOwnableOverrides_ProjectDoesNotExist`.
- Error names removed or replaced:
  - `JBOwnableOverrides_InvalidNewOwner`, `JBOwnableOverrides_ProjectDoesNotExist`.

Shared ABI artifacts checked with no ABI item changes:
- `IJBOwnable`.

## Migration Notes

- V5 integrations that only read the interface may not need calldata changes, but they should update error handling and ownership-resolution assumptions.
- Re-check automation that transfers ownership to a project before or around project creation. V6 is more explicit about invalid project ownership states.
