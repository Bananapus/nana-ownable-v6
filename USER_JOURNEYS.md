# User Journeys

## Who This Repo Serves

- contracts that should be controlled by a Juicebox project instead of a fixed wallet
- teams delegating `onlyOwner` access to project-scoped operators
- auditors reviewing whether ownership burn or transfer semantics can strand admin control

## Journey 1: Give A Contract To A Juicebox Project Instead Of A Wallet

**Starting state:** a downstream contract wants familiar `Ownable` ergonomics, but the true owner should follow a project NFT.

**Success:** `owner()` resolves to the current holder of the configured project instead of a hard-coded address.

**Flow**
1. Inherit `JBOwnable` or `JBOwnableOverrides` in the downstream contract.
2. Initialize ownership with the relevant project ID and the `JBProjects` dependency it should consult.
3. Any later transfer of the project NFT automatically changes who the downstream contract sees as the owner.

## Journey 2: Delegate Owner-Level Access To Operators

**Starting state:** the project owner wants someone other than the NFT holder to satisfy `onlyOwner` for a specific contract.

**Success:** delegated operators can use the contract through a single permission ID instead of blanket ownership transfer.

**Flow**
1. Choose the permission ID the downstream contract should respect.
2. Grant that permission through `JBPermissions` to the desired operator.
3. `JBOwnableOverrides` treats the operator as satisfying `onlyOwner` for that contract while ordinary project ownership remains unchanged.

## Journey 3: Change The Delegated Permission ID Without Changing Ownership

**Starting state:** the contract should still follow the same owner, but the permission bit that grants delegated `onlyOwner` access needs to change.

**Success:** delegation policy changes without changing the underlying owner address or project.

**Flow**
1. Call the permission-ID update surface as the current effective owner.
2. Re-grant the new permission through `JBPermissions` to whatever operators should retain access.
3. Re-audit operator assumptions because old delegations no longer satisfy `onlyOwner` once the ID changes.

## Journey 4: Transfer Or Burn Ownership Deliberately

**Starting state:** the downstream contract's admin model needs to change permanently.

**Success:** ownership changes happen with a clear understanding of whether control remains recoverable.

**Flow**
1. Transfer to a different project or address if governance should continue elsewhere.
2. Remember that ownership transfers reset the delegated permission ID, so delegation policy must be re-established on the new owner if needed.
3. Burn or renounce only when permanent admin loss is an intentional outcome.
4. Audit downstream assumptions first because some integrations cannot function once ownership is gone.

## Hand-Offs

- Use [nana-core-v6](../nana-core-v6/USER_JOURNEYS.md) for the project-NFT and permission machinery this adapter depends on.
- Use [nana-permission-ids-v6](../nana-permission-ids-v6/USER_JOURNEYS.md) if you need the shared numeric permission vocabulary for delegated `onlyOwner` checks.
