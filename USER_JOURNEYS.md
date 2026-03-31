# User Journeys

## Who This Repo Serves

- contract authors who want ownership to follow a Juicebox project
- operators who want delegated `onlyOwner` access without hard-coding one wallet
- auditors reviewing whether ownership survives project NFT transfers

## Journey 1: Give A Contract To A Juicebox Project Instead Of A Wallet

**Starting state:** you are writing or deploying a contract that would normally inherit OpenZeppelin `Ownable`.

**Success:** control of that contract follows the holder of a project NFT.

**Flow**
1. Inherit `JBOwnable` instead of plain `Ownable`.
2. Initialize ownership to a project ID rather than a fixed address.
3. Whenever `owner()` or `onlyOwner` is evaluated, the contract resolves the current holder of that project NFT.
4. If the project NFT changes hands, effective ownership follows that new holder without another admin transaction on the owned contract.

## Journey 2: Delegate Owner-Level Access To Operators

**Starting state:** the project-controlled contract has a real owner but trusted operators also need access.

**Success:** operator access is granted through Juicebox permissions rather than private-key sharing.

**Flow**
1. Set the `permissionId` that this contract should treat as owner-level access.
2. Grant that permission through `JBPermissions` to the intended operator addresses.
3. Those operators can then pass `onlyOwner` checks on this contract.
4. If ownership moves, the new owner must re-establish the permission mapping they want.

## Journey 3: Understand The Failure Mode Of Burned Ownership

**Starting state:** ownership is tied to a project NFT.

**Success:** you know the irreversible edge case before you adopt the pattern.

**Flow**
1. If the project NFT becomes unreachable or burned, owner resolution falls through to `address(0)`.
2. `onlyOwner` calls then become impossible.
3. In practice, this behaves like permanent renunciation.

**Use this repo when:** ownership should follow project governance.
**Do not use it when:** you need a recoverable admin path after project-NFT loss.
