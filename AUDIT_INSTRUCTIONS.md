# Audit Instructions -- nana-ownable-v6

You are auditing a Juicebox-aware ownership module that extends OpenZeppelin's Ownable pattern. A contract inheriting `JBOwnable` can be owned by a Juicebox project (via its ERC-721 NFT) or a direct address, with delegated access through `JBPermissions`. This is a foundational access control primitive used by hooks and extensions across the Juicebox V6 ecosystem. Read [RISKS.md](./RISKS.md) first -- it documents all known risks and trust assumptions. Then come back here.

## Compiler and Version Info

| Setting | Value |
|---------|-------|
| Solidity version | 0.8.26 |
| EVM target | cancun |
| Optimizer | enabled, 200 runs |
| via-IR | not enabled |
| Fuzz runs | 4,096 |
| Invariant runs | 1,024 (depth 100) |

Source: [`foundry.toml`](./foundry.toml)

## Previous Audit Findings

A Nemesis automated audit was conducted on 2026-03-17. Results are in [`.audit/findings/nemesis-verified.md`](./.audit/findings/nemesis-verified.md). Summary:

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| NM-001 | LOW | Constructor lacks explicit project existence check (informational) | Open (developer experience only, no security impact) |
| NM-002 | LOW | `_emitTransferEvent` try-catch asymmetry (design tradeoff) | Open (by design -- write operations should revert, not silently emit incorrect events) |

Three false positives were also eliminated during the audit (OOG attack on `_checkOwner`, wildcard permission bypass, permission delegation ownership theft). No CRITICAL, HIGH, or MEDIUM findings were identified.

No prior formal audit with finding IDs from an external security firm has been conducted.

## Error Reference

| Error | Contract | Trigger Condition |
|-------|----------|-------------------|
| `JBOwnableOverrides_InvalidNewOwner()` | JBOwnableOverrides | Constructor called with both `initialOwner == address(0)` and `initialProjectIdOwner == 0`; also `transferOwnership` called with `newOwner == address(0)` |
| `JBOwnableOverrides_ProjectDoesNotExist()` | JBOwnableOverrides | `transferOwnershipToProject` called with `projectId > PROJECTS.count()` (project does not exist) |
| `JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner()` | JBOwnableOverrides | Constructor called with `initialProjectIdOwner != 0` but `address(projects) == address(0)` |

## Scope

**In scope -- all Solidity in `src/`:**
```
src/JBOwnable.sol                  # Concrete implementation with onlyOwner modifier (~76 lines)
src/JBOwnableOverrides.sol         # Abstract base with all ownership logic (~244 lines)
src/structs/JBOwner.sol            # Owner struct: {owner, projectId, permissionId} (~15 lines)
src/interfaces/IJBOwnable.sol      # Interface (~47 lines)
```

**Out of scope:** Test files, JB Core contracts (`JBPermissioned`, `IJBPermissions`, `IJBProjects`), OpenZeppelin contracts, forge-std. Assume these dependencies are correct.

## Architecture

### Ownership Model

The `JBOwner` struct packs into a single 256-bit storage slot:

```solidity
struct JBOwner {
    address owner;       // 160 bits -- direct owner (used when projectId == 0)
    uint88 projectId;    // 88 bits  -- JB project whose NFT holder is owner (used when != 0)
    uint8 permissionId;  // 8 bits   -- JBPermissions ID for delegated access
}
```

**Resolution rules:**
1. If `projectId != 0`: owner = `PROJECTS.ownerOf(projectId)` (external call, try-catch wrapped)
2. If `projectId == 0`: owner = `jbOwner.owner` (storage read)
3. If the `ownerOf` call reverts (e.g., burned NFT): owner resolves to `address(0)`, effectively renouncing the contract

**Delegated access:** `_checkOwner()` calls `_requirePermissionFrom(resolvedOwner, projectId, permissionId)` from `JBPermissioned`. This passes if `msg.sender == resolvedOwner` OR if `msg.sender` has the configured `permissionId` (or ROOT) in `JBPermissions`.

### Inheritance Chain

```
JBOwnable (concrete)
  extends JBOwnableOverrides (abstract)
    extends Context (OpenZeppelin)
    extends JBPermissioned (nana-core)
    implements IJBOwnable (interface)
```

`JBOwnable` adds the `onlyOwner` modifier and implements `_emitTransferEvent`. `JBOwnableOverrides` contains all state management, transfer logic, and the `_checkOwner` function. Contracts that need custom `_emitTransferEvent` behavior inherit `JBOwnableOverrides` directly.

### Key Functions

| Function | Access | What it does |
|----------|--------|--------------|
| `owner()` | `public view` | Resolves and returns the current owner address. Makes an external call to `PROJECTS.ownerOf()` when project-owned. |
| `transferOwnership(address newOwner)` | `onlyOwner` | Transfers ownership to a direct address. Reverts on `address(0)`. Resets `permissionId` to 0. |
| `transferOwnershipToProject(uint256 projectId)` | `onlyOwner` | Transfers ownership to a JB project. Validates: non-zero, fits `uint88`, project exists (`<= PROJECTS.count()`). Resets `permissionId` to 0. |
| `renounceOwnership()` | `onlyOwner` | Sets owner to `address(0)` and projectId to 0. Irreversible. |
| `setPermissionId(uint8 permissionId)` | `onlyOwner` | Sets which JBPermissions ID grants delegated owner access. |
| `_checkOwner()` | `internal view` | Resolves owner, then calls `_requirePermissionFrom`. Used by `onlyOwner` modifier. |
| `_transferOwnership(address, uint88)` | `internal` | Core transfer logic. Updates `jbOwner`, resets `permissionId`, calls `_emitTransferEvent`. No access restriction. |

## Priority Audit Areas

### 1. Ownership Resolution Correctness (Highest Priority)

The `owner()` and `_checkOwner()` functions both resolve ownership via the same pattern but are separate implementations (not shared helper). Verify:

- **Consistency between `owner()` and `_checkOwner()`.** Both use try-catch on `PROJECTS.ownerOf()` and fall back to `address(0)` on revert. Verify they always agree on who the owner is. A divergence could allow someone to pass `_checkOwner()` while `owner()` returns a different address (or vice versa).
- **Try-catch scope.** The try-catch catches ALL reverts from `PROJECTS.ownerOf()`, including out-of-gas. Could an attacker force an OOG in the external call to make `_checkOwner()` resolve to `address(0)`, then bypass access control? (This would require `_requirePermissionFrom(address(0), ...)` to pass, which should not be possible for any non-zero `msg.sender` unless they have ROOT permission for the project.)
- **Zero-address as resolved owner.** When the resolved owner is `address(0)` (burned NFT or renounced), `_requirePermissionFrom(address(0), projectId, permissionId)` should revert for any caller. Verify this holds in `JBPermissioned` -- specifically that `msg.sender != address(0)` and no permission is granted to `address(0)`.

### 2. Ownership Transfer State Machine

Ownership transitions must be airtight:

- **Mutual exclusivity.** `_transferOwnership(address newOwner, uint88 projectId)` reverts if both are non-zero. Verify there is no code path that sets both `jbOwner.owner` and `jbOwner.projectId` to non-zero values simultaneously.
- **Permission reset.** Every ownership transfer resets `permissionId` to 0. Verify this happens in `_transferOwnership` (it does -- the entire `JBOwner` struct is overwritten). Verify there is no path to transfer ownership without going through `_transferOwnership`.
- **Constructor validation.** The constructor rejects `(address(0), 0)` as initial owner (both zero). It also rejects `(non-zero projectId, address(0) projects)`. Verify these are the only two invalid initial states.
- **Project existence check.** `transferOwnershipToProject` checks `projectId <= PROJECTS.count()`. Verify this prevents transferring to a non-existent project. Note: `PROJECTS.count()` returns the total number of projects ever created, and project IDs are sequential starting from 1.

### 3. Permission Delegation Security

`_checkOwner()` delegates to `_requirePermissionFrom(resolvedOwner, projectId, permissionId)`. Verify:

- **When `permissionId == 0`.** Permission ID 0 is forbidden in `JBPermissions` (cannot be set). This means when `permissionId` is 0 (the default after any transfer), ONLY the resolved owner or ROOT holders can pass `_checkOwner()`. Delegated access is effectively disabled until `setPermissionId()` is called.
- **ROOT override.** ROOT (permission ID 1) always grants access via `_requirePermissionFrom`. An address with ROOT for the relevant project can act as owner of any `JBOwnable` contract owned by that project, regardless of the configured `permissionId`. Verify this is intentional and documented.
- **Wildcard project ID.** Permissions granted with `projectId = 0` in `JBPermissions` apply to all projects. Verify that a wildcard ROOT grant (which `JBPermissions` should reject) cannot be used to bypass `_checkOwner()`.

### 4. Renunciation Edge Cases

- **Renouncing when project-owned.** If `projectId != 0` and the NFT holder calls `renounceOwnership()`, both `owner` and `projectId` are set to 0. Verify the NFT holder can still call `renounceOwnership()` (passes `_checkOwner` with the project-resolved owner).
- **Implicit renunciation via unreachable `ownerOf`.** JBProjects V6 has no burn function, so `PROJECTS.ownerOf()` cannot revert for a valid project ID under normal conditions. The try-catch in `owner()` and `_checkOwner()` is a defensive measure against hypothetical future changes to `JBProjects` or unexpected ERC-721 behavior. If `ownerOf` ever did revert, `owner()` would return `address(0)` and `_checkOwner()` would revert for all callers -- the contract would be effectively renounced without anyone calling `renounceOwnership()`. Verify this state is consistent and cannot be escaped.
- **Double renounce.** After renouncing, calling `renounceOwnership()` again should revert because `_checkOwner()` will fail (resolved owner is `address(0)` and `msg.sender` cannot be `address(0)`).

### 5. Storage Slot Packing

The `JBOwner` struct fits in a single 256-bit slot: `address` (160) + `uint88` (88) + `uint8` (8) = 256. Verify:
- The Solidity compiler lays out the struct as expected (no padding gaps).
- The `_transferOwnership` function writes the entire struct atomically (`jbOwner = JBOwner({...})`), preventing partial-write inconsistencies.

## Invariants to Verify

1. **Mutual exclusivity**: At no point can both `jbOwner.owner != address(0)` and `jbOwner.projectId != 0`.
2. **Transfer resets permission**: After any call to `_transferOwnership`, `jbOwner.permissionId == 0`.
3. **Renounce is terminal**: After `renounceOwnership()`, `jbOwner.owner == address(0)` AND `jbOwner.projectId == 0` AND all subsequent `_checkOwner()` calls revert.
4. **owner() consistency**: `owner()` and the resolved owner in `_checkOwner()` always agree.
5. **No unauthorized transfer**: Only addresses passing `_checkOwner()` can call `transferOwnership`, `transferOwnershipToProject`, `renounceOwnership`, or `setPermissionId`.

## Testing Setup

```bash
cd nana-ownable-v6
npm install
forge build
forge test

# Run attack scenarios
forge test --match-contract OwnableAttacks -vvv

# Run edge cases
forge test --match-contract OwnableEdgeCases -vvv

# Run invariant tests
forge test --match-contract OwnableInvariant -vvv

# Run regression tests
forge test --match-path test/regression/ -vvv

# Write a PoC (create test/YourExploit.t.sol)
forge test --match-path test/YourExploit.t.sol -vvv
```

## Error Reference

All custom errors are defined in `src/JBOwnableOverrides.sol`.

| Error | Trigger Condition |
|-------|-------------------|
| `JBOwnableOverrides_InvalidNewOwner()` | (1) Constructor called with both `initialOwner == address(0)` and `initialProjectIdOwner == 0`. (2) `transferOwnership()` called with `newOwner == address(0)`. (3) `transferOwnershipToProject()` called with `projectId == 0` or `projectId > type(uint88).max`. (4) `_transferOwnership(address, uint88)` called with both `newOwner != address(0)` and `projectId != 0`. |
| `JBOwnableOverrides_ProjectDoesNotExist()` | `transferOwnershipToProject()` called with a `projectId` greater than `PROJECTS.count()` (the project has not been minted yet). |
| `JBOwnableOverrides_ZeroAddressProjectsWithProjectOwner()` | Constructor called with `initialProjectIdOwner != 0` and `address(projects) == address(0)`. Prevents deploying with project-based ownership when no `JBProjects` contract is provided. |

## Previous Audit Findings

A Nemesis audit (Feynman + State Inconsistency methodology) was conducted on 2026-03-17. Full results are in `.audit/findings/nemesis-verified.md`.

**Result: 0 Critical | 0 High | 0 Medium | 2 Low (informational)**

| ID | Severity | Summary |
|----|----------|---------|
| NM-001 | LOW | Constructor lacks explicit project existence check -- deploys with a non-existent `initialProjectIdOwner` revert with an opaque ERC-721 error instead of `JBOwnableOverrides_ProjectDoesNotExist()`. Developer experience only, no security impact. |
| NM-002 | LOW | `_emitTransferEvent` in `JBOwnable` does not use try-catch for `PROJECTS.ownerOf()`, unlike `owner()` and `_checkOwner()`. This is a deliberate design tradeoff: write-path failures should revert (preventing incorrect event data), while read-path failures degrade gracefully. |

No other formal audit with finding IDs has been conducted.

## How to Report Findings

**Severity guide:**
- **CRITICAL**: Direct fund loss, permanent DoS, or broken core invariant. Exploitable with no preconditions.
- **HIGH**: Conditional fund loss, privilege escalation, or broken invariant. Requires specific but realistic setup.
- **MEDIUM**: Value leakage, griefing with cost to attacker, incorrect accounting, degraded functionality.
- **LOW**: Informational, cosmetic, edge-case-only with no material impact.

For each finding:

1. **Title** -- one line, starts with severity (CRITICAL/HIGH/MEDIUM/LOW)
2. **Affected contract(s)** -- exact file path and line numbers
3. **Description** -- what's wrong, in plain language
4. **Trigger sequence** -- step-by-step, minimal steps to reproduce
5. **Impact** -- what an attacker gains, what a user loses (with numbers if possible)
6. **Proof** -- code trace showing the exact execution path, or a Foundry test
7. **Fix** -- minimal code change that resolves the issue

## Compiler and Version Info

From `foundry.toml`:

| Setting | Value |
|---------|-------|
| Solidity version | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Fuzz runs | 4,096 |
| Invariant runs | 1,024 (depth 100) |

Go break it.
