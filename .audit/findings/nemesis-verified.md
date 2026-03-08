# N E M E S I S — Verified Findings

## Scope
- **Language:** Solidity ^0.8.26
- **Modules analyzed:** `JBOwnable`, `JBOwnableOverrides`, `IJBOwnable`, `JBOwner`
- **Functions analyzed:** 10 (6 public/external, 4 internal)
- **Coupled state pairs mapped:** 3
- **Mutation paths traced:** 2 (full struct replace, partial field write)
- **Nemesis loop iterations:** 2 (converged after Pass 1 Feynman + Pass 2 State)
- **No `script/` directory** — zero deploy scripts exist

---

## Nemesis Map (Phase 1 Cross-Reference)

```
┌───────────────────────────────┬───────────┬──────────────┬──────────────┬────────────┐
│ Function                      │ Writes    │ Writes       │ Resets       │ Sync       │
│                               │ owner     │ projectId    │ permissionId │ Status     │
├───────────────────────────────┼───────────┼──────────────┼──────────────┼────────────┤
│ _transferOwnership(addr,pid)  │ YES       │ YES          │ YES (to 0)   │ SYNCED     │
│ _setPermissionId(pid)         │ N/A       │ N/A          │ YES          │ SYNCED     │
│ constructor                   │ YES (via  │ YES (via     │ YES (via     │ SYNCED     │
│                               │ _tOwn)    │ _tOwn)       │ _tOwn)       │            │
└───────────────────────────────┴───────────┴──────────────┴──────────────┴────────────┘

Architecture: Single mutation point. ALL ownership state changes funnel through
_transferOwnership(address, uint88) which atomically replaces the full JBOwner struct.
This eliminates partial-update and coupled-state bugs by construction.
```

---

## Verification Summary

| ID | Source | Coupled Pair | Breaking Op | Severity | Verdict |
|----|--------|-------------|-------------|----------|---------|
| NM-L-001 | Feynman (Q4 Assumptions) | projectId ↔ PROJECTS | `owner()` / `_checkOwner()` | LOW | TRUE POSITIVE |
| NM-L-002 | Feynman (Q4 Assumptions) | PROJECTS ↔ PERMISSIONS | constructor | LOW | TRUE POSITIVE |

---

## Verified Findings (TRUE POSITIVES only)

### Finding NM-L-001: Project burn/invalidation could permanently lock contract

**Severity:** LOW
**Source:** Feynman Pass 1, Category 4 (Assumptions)
**Verification:** Code trace (Method A)

**Feynman Question that exposed it:**
> Q4.2: "What does `PROJECTS.ownerOf()` assume about the project's continued existence?"

**The code:**
```solidity
// JBOwnableOverrides.sol:78-86
function owner() public view virtual returns (address) {
    JBOwner memory ownerInfo = jbOwner;
    if (ownerInfo.projectId == 0) {
        return ownerInfo.owner;
    }
    return PROJECTS.ownerOf(ownerInfo.projectId); // <-- reverts if project burned
}

// JBOwnableOverrides.sol:93-101
function _checkOwner() internal view virtual {
    JBOwner memory ownerInfo = jbOwner;
    _requirePermissionFrom({
        account: ownerInfo.projectId == 0
            ? ownerInfo.owner
            : PROJECTS.ownerOf(ownerInfo.projectId), // <-- reverts if project burned
        projectId: ownerInfo.projectId,
        permissionId: ownerInfo.permissionId
    });
}
```

**Assumption:** `PROJECTS.ownerOf(projectId)` will always succeed for any `projectId` that was valid at transfer time. This relies on JBProjects V6 never supporting token burning.

**Trigger Sequence:**
1. Deploy JBOwnable with `projectId = P`
2. (Hypothetical) Project P's NFT is burned via a future JBProjects upgrade or migration
3. `owner()` reverts — no one can query the owner
4. `_checkOwner()` reverts — no one can call any `onlyOwner` function
5. `transferOwnership()`, `transferOwnershipToProject()`, `renounceOwnership()` all revert
6. Contract is permanently locked — no recovery path

**Consequence:**
- The JBOwnable contract becomes permanently inaccessible. Whatever `onlyOwner` functions it guards can never be called again.
- **Current risk: NONE.** JBProjects V6 does not support burning project NFTs.

**Verification Evidence:**
- JBProjects inherits from ERC-721. Standard `ownerOf()` reverts with `ERC721NonexistentToken` for non-existent token IDs.
- `transferOwnershipToProject()` at L149 validates existence at transfer time (`projectId > PROJECTS.count()`), but there is no ongoing existence check.
- JBProjects V6 has no public `burn()` function. Projects are permanent.

---

### Finding NM-L-002: Zero-address PROJECTS/PERMISSIONS at deployment

**Severity:** LOW
**Source:** Feynman Pass 1, Category 4 (Assumptions)
**Verification:** Code trace (Method A)

**Feynman Question that exposed it:**
> Q4.1: "What if PROJECTS or PERMISSIONS is set to address(0) in the constructor?"

**The code:**
```solidity
// JBOwnableOverrides.sol:52-71
constructor(
    IJBPermissions permissions,
    IJBProjects projects,
    address initialOwner,
    uint88 initialProjectIdOwner
) JBPermissioned(permissions) {
    PROJECTS = projects; // <-- no zero-address check
    // ...
}
```

**Scenario:**
- If `projects` is `address(0)` and `initialProjectIdOwner != 0`: constructor calls `_transferOwnership` which calls `PROJECTS.ownerOf()` → reverts. Deployment fails. **Self-protecting.**
- If `projects` is `address(0)` and `initialProjectIdOwner == 0`: deployment succeeds with address-based ownership. Later calling `transferOwnershipToProject()` would revert at `PROJECTS.count()`. Project-based ownership permanently unavailable.
- If `permissions` is `address(0)`: owner can still call directly (sender == account bypasses permission check), but delegation via `hasPermission` reverts. Degraded functionality.

**Consequence:** Misconfiguration at deployment time. Not exploitable — deployer harms only themselves.

**Verification Evidence:** Confirmed by tracing constructor → `_transferOwnership` → `PROJECTS.ownerOf()` call chain. The self-reverting behavior for invalid PROJECTS + projectId prevents the most dangerous case.

---

## False Positives Eliminated

None. No C/H/M findings were produced by any pass.

## Downgraded Findings

None. Both findings were initially assessed as LOW and remain LOW.

## Feedback Loop Discoveries

No cross-feed findings emerged. The codebase's single-mutation-point architecture means Feynman suspects did not reveal state gaps (Pass 2 found none), and State gaps did not require Feynman re-interrogation (no gaps existed).

---

## Architectural Strengths Identified

This codebase demonstrates several design patterns that actively prevent the bug classes Nemesis hunts for:

1. **Single Mutation Point:** ALL ownership state changes go through `_transferOwnership(address, uint88)`. No function bypasses this. This eliminates the #1 source of coupled state bugs — multiple code paths that update some fields but not others.

2. **Atomic Struct Replacement:** `_transferOwnership` writes the ENTIRE `JBOwner` struct in one operation (`jbOwner = JBOwner({...})`), not individual fields. This prevents partial updates and ensures `permissionId` is always reset.

3. **Consistent Access Control:** Every public state-changing function gates on `_checkOwner()`. No function uses a different authorization mechanism or skips the check.

4. **Immutable Dependencies:** `PROJECTS` and `PERMISSIONS` are `immutable`, set once in the constructor. No state inconsistency from changing external dependencies.

5. **Correct Checks-Effects-Interactions:** State is updated before external calls (`_emitTransferEvent`). External calls are read-only (`PROJECTS.ownerOf`).

6. **Dynamic Owner Resolution:** Project-based ownership resolves the owner at query time via `PROJECTS.ownerOf()`, not a cached address. This means the JBOwnable always follows the current project NFT holder without any update transaction.

---

## Summary

- **Total functions analyzed:** 10
- **Coupled state pairs mapped:** 3
- **Nemesis loop iterations:** 2 (converged)
- **Multi-tx sequences tested:** 5
- **Raw findings (pre-verification):** 0 CRITICAL | 0 HIGH | 0 MEDIUM | 2 LOW
- **Feedback loop discoveries:** 0 (neither auditor found gaps for the other to interrogate)
- **After verification:** 2 TRUE POSITIVE | 0 FALSE POSITIVE | 0 DOWNGRADED
- **Final: 0 CRITICAL | 0 HIGH | 0 MEDIUM | 2 LOW**

The `nana-ownable-v6` codebase is clean and well-architected. The single-mutation-point design for ownership state is the key structural decision that prevents coupled-state bugs. The two LOW findings are documented assumptions about deployment configuration and external dependency behavior, not exploitable vulnerabilities.
