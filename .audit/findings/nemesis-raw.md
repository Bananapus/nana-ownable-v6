# N E M E S I S — Raw Findings (Pre-Verification)

## Audit Metadata
- **Language:** Solidity ^0.8.26
- **Scope:** `src/JBOwnable.sol`, `src/JBOwnableOverrides.sol`, `src/interfaces/IJBOwnable.sol`, `src/structs/JBOwner.sol`
- **No `script/` directory** — zero deploy scripts in scope
- **Passes completed:** 2 (Pass 1 Feynman + Pass 2 State) — converged

---

## Phase 0: Attacker's Hit List

### Attack Goals
1. Gain unauthorized owner access (call `onlyOwner` functions)
2. Permanently take over ownership (steal control)
3. Lock the contract permanently (DoS the owner)
4. Bypass permission reset on transfer (stale delegation)
5. Prevent legitimate owner from exercising ownership

### Novel Code
- `JBOwnableOverrides` — dual ownership model (address OR project ID) with `permissionId` delegation
- `_transferOwnership(address, uint88)` — atomic struct replacement with mutual exclusivity enforcement
- `_checkOwner()` integration with `JBPermissions` — delegated access via configurable `permissionId`

### Value Stores
- `jbOwner` struct — the sole mutable state. Controls who can call `onlyOwner` functions.
- No funds held directly. Value is the ownership itself.

### Priority Targets
1. `_transferOwnership(address, uint88)` — all state mutations funnel here
2. `_checkOwner()` — authorization gate
3. `constructor` — initialization
4. `transferOwnershipToProject(uint256)` — most complex public function
5. `_setPermissionId(uint8)` — partial state write

---

## Phase 1: Dual Mapping

### Function-State Matrix

| Function | Reads | Writes | Guards | External Calls |
|----------|-------|--------|--------|----------------|
| `owner()` | `jbOwner` | — | — | `PROJECTS.ownerOf()` |
| `_checkOwner()` | `jbOwner` | — | — | `PROJECTS.ownerOf()`, `PERMISSIONS.hasPermission()` |
| `renounceOwnership()` | `jbOwner` | `jbOwner` | `_checkOwner()` | `PROJECTS.ownerOf()` |
| `setPermissionId(uint8)` | `jbOwner` | `jbOwner.permissionId` | `_checkOwner()` | `PROJECTS.ownerOf()` |
| `transferOwnership(address)` | `jbOwner` | `jbOwner` | `_checkOwner()` | `PROJECTS.ownerOf()` |
| `transferOwnershipToProject(uint256)` | `jbOwner` | `jbOwner` | `_checkOwner()` | `PROJECTS.ownerOf()`, `PROJECTS.count()` |
| `_setPermissionId(uint8)` | — | `jbOwner.permissionId` | — | — |
| `_transferOwnership(address)` | — | — | — | delegates to 2-arg |
| `_transferOwnership(address,uint88)` | `jbOwner` | `jbOwner` (full) | — | `PROJECTS.ownerOf()` |
| `_emitTransferEvent()` | — | — | — | `PROJECTS.ownerOf()` |

### Coupled State Dependency Map

```
PAIR 1: jbOwner.owner <-> jbOwner.projectId
  Invariant: Cannot both be non-zero simultaneously
  Mutation: _transferOwnership(address,uint88) — enforces at L190

PAIR 2: jbOwner.permissionId <-> ownership (owner/projectId)
  Invariant: permissionId MUST reset to 0 on any ownership change
  Mutation: _transferOwnership replaces entire struct with permissionId:0

PAIR 3: jbOwner.projectId <-> PROJECTS state (external)
  Invariant: If projectId != 0, project must exist in PROJECTS
  Validated at: transferOwnershipToProject (via PROJECTS.count())
```

### Nemesis Cross-Reference Map

| Function | Writes owner | Writes projectId | Resets permissionId | Sync Status |
|----------|-------------|-----------------|--------------------|----|
| `_transferOwnership(addr,pid)` | YES | YES | YES (to 0) | SYNCED |
| `_setPermissionId(pid)` | N/A | N/A | YES | SYNCED |
| constructor | YES (via _transferOwnership) | YES (via _transferOwnership) | YES (via _transferOwnership) | SYNCED |

**Architecture note:** Single mutation point design. ALL ownership changes go through one function (`_transferOwnership(address, uint88)`) which atomically replaces the entire struct. This eliminates partial-update bugs by construction.

---

## Pass 1: Feynman Interrogation Results

### All Functions Interrogated

Every function received full Feynman interrogation across all 7 categories. All verdicts: **SOUND**.

### Suspects

**FF-01: Project NFT burn → permanent contract lock**
- **Source:** Category 4 (Assumptions) on `_checkOwner()` and `owner()`
- **Lines:** `JBOwnableOverrides.sol:85`, `JBOwnableOverrides.sol:97`
- **Question:** "What does `PROJECTS.ownerOf()` assume about project existence?"
- **Scenario:** If JBProjects were to support burning tokens, `ownerOf(projectId)` would revert for burned projects. Both `owner()` and `_checkOwner()` call `ownerOf()`, so a project-owned JBOwnable contract would become permanently locked.
- **Mitigation:** JBProjects V6 does not support burning. The project NFT is permanent.
- **Initial Severity:** LOW

### Cross-Function Analysis

- **Guard Consistency:** All public state-changing functions use `_checkOwner()`. CONSISTENT.
- **Inverse Operation Parity:** `transferOwnership` and `transferOwnershipToProject` both delegate to `_transferOwnership`. SYMMETRIC.
- **Value Flow:** No funds flow through this contract. Ownership is the value, correctly managed.

---

## Pass 2: State Inconsistency Results

### Mutation Matrix

| State Variable | Mutating Function | Type | Updates Coupled State? |
|---------------|-------------------|------|----------------------|
| `jbOwner` (full) | `_transferOwnership(addr,pid)` | Full struct replace | YES — all fields atomic |
| `jbOwner.permissionId` | `_setPermissionId(uint8)` | Partial field write | N/A — no ownership change |

### Parallel Path Comparison

| Coupled State | `transferOwnership` | `transferOwnershipToProject` | `renounceOwnership` |
|--------------|--------------------|-----------------------------|---------------------|
| owner | SET to newOwner | SET to address(0) | SET to address(0) |
| projectId | SET to 0 | SET to pid | SET to 0 |
| permissionId | RESET to 0 | RESET to 0 | RESET to 0 |

**All paths: CONSISTENT.** No gaps.

### Masking Code Check

No defensive patterns found (no ternary clamps masking broken invariants, no try/catch swallowing, no min caps, no early exit on zero).

### State Findings

**None.** The single-mutation-point architecture eliminates coupled state bugs by construction.

---

## Convergence

Pass 2 produced zero new findings, zero new coupled pairs, zero new suspects, zero new root causes.

**Converged after 2 passes** (1 Feynman + 1 State). No further iterations needed.

---

## Multi-Transaction Journey Tracing

5 adversarial sequences tested:
1. Deploy → delegate → NFT transfer → stale delegation: **SAFE** (old delegation correctly invalidated)
2. Address transfer → old stale permissions: **SAFE** (permission reset + new owner)
3. Full ownership cycle (address → project → address → project): **SAFE** (all transitions clean)
4. Renounce → attempt recovery: **SAFE** (permanently unowned, irrecoverable by design)
5. Permission ID reuse across owners: **SAFE** (permissions scoped by account, not just ID)

No multi-transaction state corruption found.
