# Invariants of `nana-ownable-v6`

Scope: the two production contracts in `src/` — `JBOwnable` (concrete) and `JBOwnableOverrides` (abstract base) — plus their `IJBOwnable` interface in `src/interfaces/` and `JBOwner` struct in `src/structs/`. The package is a Juicebox-aware drop-in replacement for OpenZeppelin's `Ownable`: a contract inheriting `JBOwnable` resolves its owner either to a fixed address (address mode) or dynamically to the current holder of a Juicebox project's ERC-721 NFT (project mode), with an optional `JBPermissions` ID that delegates `onlyOwner` access to addresses authorized by the current resolved owner.

This file is the per-repo scoped invariants doc. The protocol-wide guarantees for the seven deployed revnets live in [`../INVARIANTS.md`](../INVARIANTS.md); `JBOwnable` itself does not appear in that file because it is a base contract — its invariants flow up into every consumer (`JB721TiersHook`, the buyback/router/Defifa hook surfaces, `CTPublisher`'s owner lookup, etc.). The cross-cutting "NFT-transfer auto-disables delegation" design contract lives in `RISKS.md` and `ARCHITECTURE.md`; this file enumerates the operational invariants that implement that contract.

---

# Section A — Guarantees to Callers of an `onlyOwner` Function

The "users" of a `JBOwnable`-inheriting contract are everyone who calls one of its `onlyOwner` functions: the resolved owner, anyone the owner has delegated to via `JBPermissions`, and any third party who might try (and must fail). There is no payer-side or holder-side surface in this repo — the package contributes only an authorization primitive.

## A.1 Owner resolution

- **A.1.1 Single-source-of-truth resolution.** Every authorization check goes through the same internal helper, `_checkOwner`, which reads `jbOwner` once into memory, resolves the owner address (project NFT holder for `projectId != 0`, stored address for `projectId == 0`), and either bypasses `JBPermissions` (when `permissionId == 0` or stale — see A.3.2) or routes through `_requirePermissionFrom` (`src/JBOwnableOverrides.sol:128–163`). There is no second auth path on the contract.
- **A.1.2 Project mode resolves dynamically.** When `jbOwner.projectId != 0`, `owner()` and `_checkOwner` call `PROJECTS.ownerOf(projectId)` at the moment of the call (`src/JBOwnableOverrides.sol:103–116, 128–141`). Transferring the project NFT immediately and atomically transfers `JBOwnable` ownership — no follow-up `transferOwnership` is required, and no stale address can be left holding `onlyOwner` rights after the NFT moves.
- **A.1.3 Fail-closed on unreadable project.** If `PROJECTS.ownerOf(projectId)` reverts (e.g., the project ID was pre-bound but the NFT has not been minted yet, or the project was burned), `owner()` returns `address(0)` and `_checkOwner` treats the resolved owner as `address(0)` (`src/JBOwnableOverrides.sol:111–115, 136–140`). Because `_msgSender()` can never equal `address(0)`, every `onlyOwner` call reverts during the unreadable window. The contract fails closed rather than opening up to the zero address.
- **A.1.4 Address mode is fixed until transfer.** When `jbOwner.projectId == 0`, the owner is `jbOwner.owner` exactly — no project lookup, no fallback. The address only changes via `transferOwnership`, `transferOwnershipToProject`, or `renounceOwnership` (`src/JBOwnableOverrides.sol:106–108, 132–133`).

## A.2 Caller authorization

- **A.2.1 Direct owner always passes.** The resolved owner can always call `onlyOwner` functions, regardless of the stored `permissionId` value — when `effectivePermissionId == 0`, the check is a plain `_msgSender() != resolvedOwner` comparison and bypasses `JBPermissions` entirely (`src/JBOwnableOverrides.sol:151–158`).
- **A.2.2 Delegate-by-permission is opt-in.** Delegation is OFF by default (`jbOwner.permissionId` is zero after construction unless the inheriting constructor sets it). The current owner must explicitly call `setPermissionId(nonzero)` for any `JBPermissions` grant to grant `onlyOwner` access on this contract (`src/JBOwnableOverrides.sol:181–184, 237–241`).
- **A.2.3 Delegation is per-resolved-owner via `_permissionOwner` snapshot.** When `setPermissionId` runs, the hook snapshots the CURRENT resolved owner into `_permissionOwner` (`src/JBOwnableOverrides.sol:239`). On every `_checkOwner` call, if `resolvedOwner != _permissionOwner`, the stored `permissionId` is treated as zero — i.e., delegation only counts while the *same* resolved owner who set the ID is still in control (`src/JBOwnableOverrides.sol:143–147`).
- **A.2.4 `JBPermissioned_Unauthorized` is the only failure mode.** A non-owner, non-delegate caller reverts `JBPermissioned.JBPermissioned_Unauthorized({account: resolvedOwner, sender: _msgSender(), projectId: ownerInfo.projectId, permissionId: 0})` (`src/JBOwnableOverrides.sol:152–155`). The same error surfaces from `_requirePermissionFrom` for failed delegate checks (with a non-zero `permissionId`).
- **A.2.5 No ROOT-on-project bypass.** `_checkOwner` calls `_requirePermissionFrom({account: resolvedOwner, projectId: ownerInfo.projectId, permissionId: effectivePermissionId})` only when `effectivePermissionId != 0` (`src/JBOwnableOverrides.sol:160–162`). When delegation is disabled (zero or stale `permissionId`), the function takes the explicit-equality branch (`src/JBOwnableOverrides.sol:151–158`) and never enters the permissions system. A third party who holds `ROOT` on the resolved owner via `JBPermissions` cannot call `onlyOwner` functions through this contract unless the owner has also set a non-zero `permissionId` (which would route through `_requirePermissionFrom`, where ROOT would then apply).

## A.3 NFT-transfer semantics (project-mode owners)

- **A.3.1 NFT transfer auto-disables delegation.** Because delegation requires `resolvedOwner == _permissionOwner` (A.2.3), the moment the project NFT moves to a new holder, every previously-delegated `JBPermissions` grant ceases to grant `onlyOwner` access on this contract. The new holder must call `setPermissionId` themselves to re-enable delegation under their identity (`src/JBOwnableOverrides.sol:143–147, 179–184`). This is the core "stale delegate" defense — buying a project NFT does not inherit the seller's delegate list.
- **A.3.2 Round-trip reactivation is by design.** If the NFT later returns to the original `_permissionOwner` (same EOA/contract address), their old delegate grants become effective again because the equality check passes again. This is the documented design contract (`src/JBOwnableOverrides.sol:18, 126–127` NatSpec). Owners who do not want this should `setPermissionId(0)` before transferring the NFT.
- **A.3.3 `permissionOwner` snapshot is forward-looking, not historical.** `_permissionOwner` is overwritten on every `setPermissionId` call (`src/JBOwnableOverrides.sol:239`) and zeroed on every `_transferOwnership` (`src/JBOwnableOverrides.sol:276`). It is not a list — only the most recent set-ID owner is tracked.
- **A.3.4 Resolution survives missing NFT.** If the project NFT is sent to `address(0)` (e.g., transferred to the zero address), `PROJECTS.ownerOf` reverts (ERC-721 contract reverts for nonexistent tokens after `_burn`), so `_checkOwner` fails closed via A.1.3. No address can call `onlyOwner` until ownership is moved out of the burned-project state via the address-mode transfer paths (which require a current owner who can still authenticate — i.e., the contract is permanently locked).

---

# Section B — Guarantees to the Owner

## B.1 Powers the owner retains

- **B.1.1 Transfer to an address.** The owner can call `transferOwnership(address newOwner)` (`src/JBOwnableOverrides.sol:191–198`) to move ownership to a fixed address. The function rejects `address(0)` with `JBOwnableOverrides_InvalidNewOwner({newOwner: address(0), projectId: 0})` — use `renounceOwnership` for that. The transfer resets `jbOwner.permissionId` to 0 and `_permissionOwner` to `address(0)`, so the new owner inherits a clean delegation slate (`src/JBOwnableOverrides.sol:274–276`).
- **B.1.2 Transfer to a project.** The owner can call `transferOwnershipToProject(uint256 projectId)` (`src/JBOwnableOverrides.sol:206–220`) to switch into project mode. The argument must fit in `uint88` (`projectId <= type(uint88).max`) and must refer to an already-minted project (`projectId <= PROJECTS.count()`), otherwise the call reverts `JBOwnableOverrides_InvalidNewOwner` or `JBOwnableOverrides_ProjectDoesNotExist` respectively. Pre-bound future project IDs are NOT permitted through this public path — that ability is reserved for the constructor (B.3.1).
- **B.1.3 Renounce.** The owner can call `renounceOwnership()` (`src/JBOwnableOverrides.sol:171–174`) to permanently disable `onlyOwner`. After renounce, `jbOwner = JBOwner(address(0), 0, 0)` and `_permissionOwner = address(0)`; every subsequent `_checkOwner` reverts because `resolvedOwner == address(0) != _msgSender()` (`src/JBOwnableOverrides.sol:151–157`). Irreversible by design.
- **B.1.4 Set or clear the delegation permission ID.** The owner can call `setPermissionId(uint8 permissionId)` (`src/JBOwnableOverrides.sol:181–184`) at any time. Setting to 0 disables delegation entirely; setting to a non-zero value also snapshots the current resolved owner into `_permissionOwner` (`src/JBOwnableOverrides.sol:237–241`).

## B.2 Powers the owner does NOT have

- **B.2.1 Cannot pre-bind a future project after deployment.** `transferOwnershipToProject` enforces `projectId <= PROJECTS.count()` (`src/JBOwnableOverrides.sol:214–216`); only the constructor can accept an unminted future ID (B.3.1).
- **B.2.2 Cannot grant delegation across an NFT transfer.** Because `_permissionOwner` is keyed to the owner *who set the ID*, the owner cannot pre-grant delegate access to a buyer who will receive the project NFT in the future — the buyer must call `setPermissionId` themselves after taking custody. NFT marketplaces and OTC transfers therefore cannot smuggle a live delegate set with the NFT.
- **B.2.3 Cannot route a transfer through both modes at once.** `_transferOwnership(newOwner, projectId)` reverts `JBOwnableOverrides_InvalidNewOwner` if both arguments are non-zero (`src/JBOwnableOverrides.sol:258–260`). The contract has exactly one live owner mode at any time: address, project, or renounced.
- **B.2.4 Cannot revive after renounce.** There is no `unrenounce` path. Once `jbOwner` is zeroed, no caller can pass `_checkOwner` to invoke `transferOwnership`, `transferOwnershipToProject`, or `setPermissionId` — they are all `_checkOwner`-gated.
- **B.2.5 Cannot bypass authentication via direct storage write.** `jbOwner` is `public` (auto-getter) but write access is internal-only. The only mutating paths are `_transferOwnership` and `_setPermissionId`, both called from `_checkOwner`-gated public functions. An inheriting contract that exposes a raw setter is its own bug, not this base's.

## B.3 Constructor pre-binding (one-shot, deployer-controlled)

- **B.3.1 Constructor accepts unminted project IDs.** The constructor calls `_transferOwnership(newOwner: initialOwner, projectId: initialProjectIdOwner)` (`src/JBOwnableOverrides.sol:92`), which does NOT enforce `projectId <= PROJECTS.count()`. This is the deliberate "pre-bind to a future project" path used by deployers that need to deploy the owned contract BEFORE the project NFT is minted (e.g., `JBOmnichainDeployer.launchProjectFor` deploys the 721 hook then transfers ownership to the project after minting; `JB721TiersHookProjectDeployer` does the same).
- **B.3.2 Constructor input must identify exactly one valid owner.** `initialProjectIdOwner == 0 && initialOwner == address(0)` reverts `JBOwnableOverrides_InvalidNewOwner` (`src/JBOwnableOverrides.sol:86–88`). Constructing in the unowned state requires the inheriting constructor to call `renounceOwnership()` explicitly (which still requires an initial owner to authenticate against — i.e., set `initialOwner = address(this)` or similar and immediately renounce in the subclass constructor).
- **B.3.3 Pre-bound owner mode resolves to `address(0)` until the project is minted.** If the constructor binds `projectId = 99` and project 99 has not been minted yet, `owner()` returns `address(0)` (A.1.3) and every `onlyOwner` call reverts until the project is created. The first account to mint that project becomes the effective owner — deployers must control the mint sequence (`src/JBOwnableOverrides.sol:65–67` NatSpec).
- **B.3.4 Pre-bound transfer event resolves new owner at emit time.** `JBOwnable._emitTransferEvent` (the concrete override) calls `PROJECTS.ownerOf(newProjectId)` with try-catch; on revert it reports `address(0)` in the event (`src/JBOwnable.sol:67–78`). The event therefore reflects the visible owner at the moment of the transfer, not a placeholder address — pre-bound future projects show up as `newOwner = address(0)` in `OwnershipTransferred` and resolve normally on later reads.

---

# Section C — Per-Contract Operation Inventory

`JBOwnable` (concrete, 80 lines) and `JBOwnableOverrides` (abstract base, 280 lines) are the only Solidity files in `src/`. The interface `IJBOwnable` and struct `JBOwner` are types, not contracts.

## C.1 `JBOwnableOverrides` — `src/JBOwnableOverrides.sol`

Abstract base. Cannot be deployed directly. All state lives here; `JBOwnable` is a thin concrete subclass that supplies the `onlyOwner` modifier and the `_emitTransferEvent` resolution.

### Constructor (one-time, deployer-controlled)

- **`constructor(IJBPermissions permissions, IJBProjects projects, address initialOwner, uint88 initialProjectIdOwner)`** (`src/JBOwnableOverrides.sol:74–93`) — called once per deployment from the inheriting contract's constructor. Reverts `JBOwnableOverrides_InvalidNewOwner` if both `initialOwner == address(0)` AND `initialProjectIdOwner == 0`. Sets `PROJECTS` immutable, calls `JBPermissioned(permissions)` for the `PERMISSIONS` immutable, then `_transferOwnership(initialOwner, initialProjectIdOwner)` to set initial `jbOwner` and zero `_permissionOwner`. The only path that can pre-bind an unminted project ID (B.3.1).
  - **Invariants:** A.1.4, B.2.3, B.3.1–B.3.4.
  - **Cannot:** be called more than once per deployed contract; produce an unowned initial state (B.3.2).

### Owner-gated mutations

- **`transferOwnership(address newOwner) public virtual override`** (`src/JBOwnableOverrides.sol:191–198`) — owner only. Calls `_checkOwner`, rejects `address(0)` with `JBOwnableOverrides_InvalidNewOwner`, then `_transferOwnership(newOwner, 0)`. Emits `OwnershipTransferred` via `_emitTransferEvent`.
  - **Invariants:** A.1, A.2, B.1.1, B.2.3.

- **`transferOwnershipToProject(uint256 projectId) public virtual override`** (`src/JBOwnableOverrides.sol:206–220`) — owner only. Calls `_checkOwner`; reverts `JBOwnableOverrides_InvalidNewOwner({newOwner: address(0), projectId: projectId})` if `projectId == 0` or `projectId > type(uint88).max`; reverts `JBOwnableOverrides_ProjectDoesNotExist({projectId, projectCount: PROJECTS.count()})` if `projectId > PROJECTS.count()` (B.1.2). On success, calls `_transferOwnership(address(0), uint88(projectId))` and emits `OwnershipTransferred`.
  - **Invariants:** A.1, A.2, B.1.2, B.2.1, B.2.3.

- **`renounceOwnership() public virtual override`** (`src/JBOwnableOverrides.sol:171–174`) — owner only. Calls `_checkOwner`, then `_transferOwnership(address(0), 0)`. Permanently disables `onlyOwner`.
  - **Invariants:** A.1, A.2, B.1.3, B.2.4.

- **`setPermissionId(uint8 permissionId) public virtual override`** (`src/JBOwnableOverrides.sol:181–184`) — owner only. Calls `_checkOwner`, then `_setPermissionId(permissionId)` (which writes `jbOwner.permissionId = permissionId`, sets `_permissionOwner = owner()` after the write, and emits `PermissionIdChanged`).
  - **Invariants:** A.2.2, A.2.3, A.3.1–A.3.3, B.1.4.

### Views

- **`owner() public view virtual returns (address)`** (`src/JBOwnableOverrides.sol:103–116`) — anyone. Returns the stored address for address mode, or the project NFT holder for project mode (with try-catch fallback to `address(0)` if `PROJECTS.ownerOf` reverts).
  - **Invariants:** A.1.1–A.1.4.
- **`jbOwner() public view returns (address owner, uint88 projectId, uint8 permissionId)`** — auto-generated getter on the public `jbOwner` storage slot. Returns the raw stored ownership state regardless of project NFT location.
- **`PROJECTS() public view returns (IJBProjects)`** — auto-generated getter on the public immutable.

### Internal helpers (not part of external surface)

- **`_checkOwner() internal view virtual`** (`src/JBOwnableOverrides.sol:128–163`) — the auth primitive. Loads `jbOwner`, resolves the current owner (project NFT lookup with fail-closed fallback to `address(0)`), zeroes a stale `permissionId` if `resolvedOwner != _permissionOwner`, then either does `_msgSender() == resolvedOwner` (delegation disabled/stale, no permissions check) or calls `_requirePermissionFrom({account: resolvedOwner, projectId: ownerInfo.projectId, permissionId: effectivePermissionId})`.
  - **Invariants:** A.1, A.2, A.3.1, A.3.2.
- **`_transferOwnership(address newOwner) internal virtual`** (`src/JBOwnableOverrides.sol:245–247`) — OpenZeppelin-compatible single-arg overload; delegates to `_transferOwnership(newOwner, 0)`. Lets inheriting contracts use OZ-style flows without knowing about project mode.
- **`_transferOwnership(address newOwner, uint88 projectId) internal virtual`** (`src/JBOwnableOverrides.sol:256–279`) — the canonical mutator. Reverts if both `newOwner` and `projectId` are non-zero (B.2.3). Resolves the previous owner with the same try-catch pattern as `owner()` for the event. Overwrites `jbOwner` with `(newOwner, projectId, 0)`, zeros `_permissionOwner`, emits via `_emitTransferEvent`.
  - **Invariants:** A.1.4, A.3.3, B.2.3.
- **`_setPermissionId(uint8 permissionId) internal virtual`** (`src/JBOwnableOverrides.sol:237–241`) — writes `jbOwner.permissionId = permissionId`, then sets `_permissionOwner = owner()`. **Order matters:** `_permissionOwner` is set AFTER the `permissionId` write, but is read AFTER the resolved owner is computed via `owner()`; the two operations cannot interleave because Solidity has no concurrency. If `setPermissionId(X)` is called by a delegate (not the direct owner), `_permissionOwner` is still set to the current resolved owner, not the caller — delegates can rotate the permission ID but cannot change WHO the delegation belongs to.
  - **Invariants:** A.2.3, A.3.3, B.1.4.
- **`_emitTransferEvent(address previousOwner, address newOwner, uint88 newProjectId) internal virtual`** — abstract; supplied by `JBOwnable`.

### Storage layout (load-bearing for delegation semantics)

- **`JBOwner public jbOwner`** (`src/JBOwnableOverrides.sol:46`) — packed `(address owner, uint88 projectId, uint8 permissionId)` totalling 184 bits, fits in one storage slot. `owner` only used when `projectId == 0`. `permissionId == 0` means "no delegation."
- **`address internal _permissionOwner`** (`src/JBOwnableOverrides.sol:54`) — the resolved owner at the time `permissionId` was last set. Reset to `address(0)` on `_transferOwnership`, overwritten on `_setPermissionId`. The mismatch check `resolvedOwner != _permissionOwner` in `_checkOwner` (`src/JBOwnableOverrides.sol:145`) is what implements NFT-transfer auto-disable (A.3.1).
- **`IJBProjects public immutable PROJECTS`** (`src/JBOwnableOverrides.sol:39`) — set in constructor, used by `owner()`, `_checkOwner`, `_transferOwnership`, and `transferOwnershipToProject`.
- **`IJBPermissions public immutable PERMISSIONS`** — inherited from `JBPermissioned`, used by `_requirePermissionFrom` indirectly during delegation checks.

### Errors

- **`JBOwnableOverrides_InvalidNewOwner(address newOwner, uint256 projectId)`** — emitted on constructor double-zero (B.3.2), `transferOwnership(address(0))` (B.1.1), `transferOwnershipToProject(0 | > uint88.max)` (B.1.2), or `_transferOwnership` with both fields non-zero (B.2.3).
- **`JBOwnableOverrides_ProjectDoesNotExist(uint256 projectId, uint256 projectCount)`** — emitted by `transferOwnershipToProject` when the public path is asked to bind a future project ID (B.1.2, B.2.1).
- **`JBPermissioned.JBPermissioned_Unauthorized(account, sender, projectId, permissionId)`** — emitted by `_checkOwner` on direct-equality failure (A.2.4) or by `_requirePermissionFrom` on a failed delegate check.

### Events

- **`OwnershipTransferred(address indexed previousOwner, address indexed newOwner, address caller)`** — emitted by `_emitTransferEvent`. `newOwner` is `address(0)` for pre-bound future projects (B.3.4) and for renounce; otherwise the current resolved owner.
- **`PermissionIdChanged(uint8 newId, address caller)`** — emitted by `_setPermissionId`.

## C.2 `JBOwnable` — `src/JBOwnable.sol`

Concrete subclass (80 lines). Adds the `onlyOwner` modifier and supplies `_emitTransferEvent` resolution. Contracts inheriting `JBOwnable` get the modifier-based API; contracts that want the same logic without the modifier can inherit `JBOwnableOverrides` directly.

### Constructor

- **`constructor(IJBPermissions permissions, IJBProjects projects, address initialOwner, uint88 initialProjectIdOwner)`** (`src/JBOwnable.sol:30–37`) — forwards all four arguments positionally to `JBOwnableOverrides`. Same semantics, same one-shot rules.

### Modifier

- **`modifier onlyOwner() virtual`** (`src/JBOwnable.sol:44–47`) — calls `_checkOwner()` then continues. The single attachment point for `onlyOwner`-gated functions in inheriting contracts.
  - **Invariants:** A.1, A.2, A.3.

### Override

- **`_emitTransferEvent(address previousOwner, address newOwner, uint88 newProjectId) internal virtual override`** (`src/JBOwnable.sol:59–79`) — resolves the new owner's current address for the event when transferring to a project: tries `PROJECTS.ownerOf(newProjectId)` and falls back to `address(0)` on revert. The previous owner is resolved by `_transferOwnership` itself (with its own try-catch); this override only handles the new side.
  - **Invariants:** B.3.4.

## C.3 `IJBOwnable` — `src/interfaces/IJBOwnable.sol`

Interface contract. Declares the public surface (`PROJECTS`, `jbOwner`, `owner`, `renounceOwnership`, `setPermissionId`, `transferOwnership`, `transferOwnershipToProject`) and the two events. No invariants of its own — it just types the surface.

## C.4 `JBOwner` — `src/structs/JBOwner.sol`

The packed storage struct: `{address owner; uint88 projectId; uint8 permissionId}`. 184 bits total — fits in a single 256-bit slot. The packing is load-bearing for gas cost (one SLOAD per `_checkOwner`) but does not affect logic.

---

# Section D — Cross-Cutting Invariants

- **D.1 Fail-closed on every unreadable owner.** Three paths read `PROJECTS.ownerOf` with try-catch — `owner()` (`src/JBOwnableOverrides.sol:111–115`), `_checkOwner` (`src/JBOwnableOverrides.sol:136–140`), and `_transferOwnership`'s previous-owner resolution (`src/JBOwnableOverrides.sol:268–272`) — and all three fall back to `address(0)`. The fourth path (`JBOwnable._emitTransferEvent`'s NEW-owner resolution) also falls back to `address(0)`. There is no path that bubbles a project-lookup revert up to the caller; the contract universally treats an unreadable project as "no owner." Because `_msgSender()` is never `address(0)` in normal EVM execution, "no owner" always means "no one can authenticate."
- **D.2 NFT transfer is the canonical re-permissioning event.** Project NFT transfers transparently and atomically: (a) move `onlyOwner` access (A.1.2), (b) invalidate every delegate grant by making `resolvedOwner != _permissionOwner` (A.3.1), and (c) leave `jbOwner.permissionId` UNCHANGED in storage (only its *effective* value flips to zero). If the NFT later returns to the original `_permissionOwner`, delegation reactivates (A.3.2). The owner can pre-empt that by calling `setPermissionId(0)` before transferring the NFT.
- **D.3 Explicit transfers always clear delegation.** `_transferOwnership` zeros `jbOwner.permissionId` AND `_permissionOwner` (`src/JBOwnableOverrides.sol:275–276`). Unlike NFT transfers (D.2), an explicit `transferOwnership` / `transferOwnershipToProject` / `renounceOwnership` does NOT preserve the old permission ID — the new owner inherits delegation OFF and must opt in via `setPermissionId`.
- **D.4 Single-owner-mode invariant.** Across the constructor and `_transferOwnership`, `jbOwner.projectId != 0 && jbOwner.owner != address(0)` is structurally rejected (`src/JBOwnableOverrides.sol:258–260, 86–88`). At every moment, the contract is in exactly one of three states: address mode (`projectId == 0, owner != 0`), project mode (`projectId != 0, owner == 0`), or renounced (`projectId == 0, owner == 0`).
- **D.5 Pre-bind-to-future-project is constructor-only.** Public `transferOwnershipToProject` enforces `projectId <= PROJECTS.count()` (`src/JBOwnableOverrides.sol:214–216`); the constructor does NOT. This is deliberate — deploy-then-mint flows need to set ownership before the project exists, but no live owner should be able to point ownership at an unminted (potentially future-claimable) project, which could let the eventual project minter sneak in (B.3.3).
- **D.6 ROOT-on-project is not a bypass.** When delegation is disabled (`permissionId == 0` or stale), `_checkOwner` takes the direct-equality branch and never queries `JBPermissions`. A holder of `ROOT` on the resolved owner cannot call `onlyOwner` through delegation that isn't enabled — they would have to hold the project NFT directly (A.2.5). This closes the "owner sells NFT, ROOT delegate keeps control" attack class.
- **D.7 `setPermissionId` snapshots the owner at write time, not the caller.** A delegate who is currently authorized (`effectivePermissionId != 0` AND a valid `JBPermissions` grant) can call `setPermissionId` — it passes `_checkOwner`. But `_permissionOwner = owner()` is set to the CURRENT RESOLVED OWNER, not `_msgSender()` (`src/JBOwnableOverrides.sol:239`). Delegates can rotate the ID; they cannot rebase delegation onto themselves.
- **D.8 No global admin, no upgrade hook, no pause.** Section E applies. The package has no `Ownable` of its own, no proxy, no `__gap`. Each consumer inherits its own owner state and runs its own lifecycle.
- **D.9 Reentrancy is irrelevant by construction.** Every mutating function is `_checkOwner`-gated and writes its own state before emitting events. There are no external calls in mutating paths except (a) `PROJECTS.ownerOf` (view, on `JBProjects` which is a vanilla ERC-721) and (b) `JBPermissions.hasPermission` (view, no state effect). The contract has no funds to drain and no value-bearing operations.
- **D.10 Constructor uses `_transferOwnership` not `transferOwnership`.** The constructor calls the INTERNAL `_transferOwnership` to install the initial owner (`src/JBOwnableOverrides.sol:92`) so the install is not gated by `_checkOwner` (which would fail because there's no owner yet). Inheriting contracts that need to renounce in the constructor should call `renounceOwnership()` from their own constructor body AFTER passing through `JBOwnable`'s constructor — `renounceOwnership` will succeed because the freshly-installed `initialOwner` is the `msg.sender` of the inheriting constructor.

---

# Section E — Centralization Caveats

**None at the library layer.** `JBOwnable` is a base contract; it has no admin, no owner of its own (the owner OF the inheriting contract is determined per-deployment by that contract's constructor args), no pause, no upgrade hook, no fee setting, no allowlist, no registry.

Each consumer contract that inherits `JBOwnable` sets its own owner at deploy time. The aggregate centralization posture of a Juicebox deployment is the union of those consumers' choices, not anything this package controls. Examples from the V6 ecosystem:

- **`JB721TiersHook`** (nana-721-hook-v6) inherits `JBOwnable`. Each tiered-721 hook clone is owned per-project: deployed by `JB721TiersHookProjectDeployer`, then ownership transferred to the project ID via `JBOwnable(address(hook)).transferOwnershipToProject(projectId)`. Subsequent owner is whoever holds that project's NFT — the project owner, generally `REVOwner` for revnets 1–7. See `nana-721-hook-v6/src/JB721TiersHookProjectDeployer.sol:110, 166, 213`.
- **`JBOmnichainDeployer`-launched hooks** (nana-omnichain-deployers-v6) follow the same pattern: `JBOwnable(address(hook)).transferOwnershipToProject(projectId)` after the project NFT is minted. See `nana-omnichain-deployers-v6/src/JBOmnichainDeployer.sol` ownership-transfer call sites.
- **`REVDeployer`-launched 721 hooks** (revnet-core-v6) transfer hook ownership to `OWNER` (the singleton REVOwner) via `JBOwnable(address(hook)).transferOwnership(OWNER)` — see `revnet-core-v6/src/REVDeployer.sol`.
- **`CTPublisher`** (croptop-core-v6) reads `JBOwnable(allowedPost.hook).owner()` to authenticate the configurer of posting criteria. The owner returned is whoever currently holds the hook's project NFT — see `croptop-core-v6/src/CTPublisher.sol:137`.

A `JBOwnable`-inheriting contract's centralization posture inherits the inheriting contract's owner posture. This package contributes a single invariant: whoever the inheriting contract identifies as owner (either a fixed address or the current project NFT holder) is the ONLY address that can call `onlyOwner`, plus any addresses the current owner has explicitly delegated to via a non-zero `permissionId` under their own identity.

Upstream centralization that affects every consumer indirectly:

- **`JBProjects`.** Project mode resolves through `PROJECTS.ownerOf`. The project NFT is a standard ERC-721; transfers/approvals follow OZ semantics. `JBProjects` itself is owned by `_CRITICAL_INFRA_OWNER` for fee/resolver settings only — it cannot rewrite who holds a given project's NFT. See `../INVARIANTS.md` Section C.10 and Section E.
- **`JBPermissions`.** Delegation routes through `PERMISSIONS.hasPermission`. The permissions contract cannot be swapped after `JBOwnable` deployment (`PERMISSIONS` is immutable). The permissions contract itself has no global admin — see `../INVARIANTS.md` Section C.8.

---

# Section F — Key Code References

| Invariant | File:lines |
|---|---|
| A.1.1, D.6 (single-source-of-truth auth via `_checkOwner`) | `src/JBOwnableOverrides.sol:128–163` |
| A.1.2 (project mode resolves dynamically) | `src/JBOwnableOverrides.sol:103–116, 132–141` |
| A.1.3, D.1 (fail-closed on unreadable project) | `src/JBOwnableOverrides.sol:111–115, 136–140, 268–272`; `src/JBOwnable.sol:70–75` |
| A.1.4, D.4 (address mode + single-mode invariant) | `src/JBOwnableOverrides.sol:106–108, 132–133, 258–260, 86–88` |
| A.2.1 (direct owner equality bypass) | `src/JBOwnableOverrides.sol:151–158` |
| A.2.2, B.1.4 (delegation opt-in) | `src/JBOwnableOverrides.sol:181–184, 237–241` |
| A.2.3, A.3.1, A.3.3, D.2, D.7 (`_permissionOwner` snapshot + NFT-transfer auto-disable) | `src/JBOwnableOverrides.sol:54, 143–147, 237–241, 275–276` |
| A.2.4 (`JBPermissioned_Unauthorized` failure mode) | `src/JBOwnableOverrides.sol:152–155` |
| A.2.5, D.6 (no ROOT-on-project bypass when delegation off) | `src/JBOwnableOverrides.sol:151–158, 160–162` |
| A.3.2 (round-trip reactivation by design) | `src/JBOwnableOverrides.sol:18, 126–127` (NatSpec) |
| B.1.1 (transferOwnership rejects address(0)) | `src/JBOwnableOverrides.sol:191–198` |
| B.1.2, B.2.1, D.5 (transferOwnershipToProject bounds) | `src/JBOwnableOverrides.sol:206–220` |
| B.1.3, B.2.4 (renounce + irreversibility) | `src/JBOwnableOverrides.sol:171–174, 256–279` |
| B.2.3, D.4 (single-owner-mode enforced) | `src/JBOwnableOverrides.sol:258–260, 86–88` |
| B.3.1, B.3.3, D.5 (constructor pre-bind path) | `src/JBOwnableOverrides.sol:74–93` |
| B.3.2 (constructor rejects double-zero) | `src/JBOwnableOverrides.sol:86–88` |
| B.3.4 (transfer event new-owner resolution) | `src/JBOwnable.sol:59–79` |
| C.1 storage layout (packed JBOwner) | `src/JBOwnableOverrides.sol:46`; `src/structs/JBOwner.sol:10–14` |
| C.1 `_permissionOwner` slot | `src/JBOwnableOverrides.sol:54` |
| C.1 PROJECTS immutable | `src/JBOwnableOverrides.sol:39` |
| C.2 `onlyOwner` modifier | `src/JBOwnable.sol:44–47` |
| D.3 (explicit transfers clear delegation) | `src/JBOwnableOverrides.sol:275–276` |
| D.10 (constructor uses internal `_transferOwnership`) | `src/JBOwnableOverrides.sol:92, 245–247, 256–279` |
| Consumer pattern: 721 hook transfer-to-project | `nana-721-hook-v6/src/JB721TiersHookProjectDeployer.sol:110, 166, 213` |
| Consumer pattern: omnichain hook transfer-to-project | `nana-omnichain-deployers-v6/src/JBOmnichainDeployer.sol:808, 861, 917` |
| Consumer pattern: REVDeployer transfer-to-address (REVOwner singleton) | `revnet-core-v6/src/REVDeployer.sol:566, 735` |
| Consumer pattern: CTPublisher owner lookup | `croptop-core-v6/src/CTPublisher.sol:137` |
