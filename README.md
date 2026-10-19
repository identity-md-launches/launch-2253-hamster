# HAMSTER (HAMSTER)

A plain, fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum.

| Field | Value |
| --- | --- |
| Solidity contract | `HamsterToken` (`src/HamsterToken.sol`) |
| Token name | `HAMSTER` |
| Token symbol | `HAMSTER` |
| Decimals | 18 |
| Total supply | 1,000,000,000 HAMSTER = `1000000000000000000000000000` minor units |
| Minting | Once, in the constructor, the whole supply to `msg.sender` (the deployer) |
| Constructor arguments | None |
| Owner / admin | None. No owner, minter, pauser, blacklist, fee, tax or burn hook |
| Base library | OpenZeppelin Contracts v5.4.0 `ERC20` (vendored under `lib/`) |
| Compiler | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"`, `cbor_metadata = false` |

## Behaviour

- The constructor mints `TOTAL_SUPPLY` to `msg.sender` and emits the standard `Transfer(0x0, deployer, supply)`
  plus a `SupplyMinted(deployer, supply)` event. Nothing can mint afterwards: there is no `mint`, no owner and
  no upgrade path, so `totalSupply()` can never exceed the launch supply.
- Transfers, approvals and `transferFrom` are the unmodified OpenZeppelin v5 implementation. Every transfer moves
  exactly the amount requested, so the launch flows (factory to distributor, pool seed, pool swaps, remainder to
  the requester) arrive whole and no address needs an exemption.
- Failure paths revert with OpenZeppelin's ERC-6093 custom errors: `ERC20InsufficientBalance`,
  `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`, `ERC20InvalidSpender`, `ERC20InvalidSender`.
- The contract has no `receive` or `fallback`, so it cannot hold ether and calls to unknown selectors revert.
- The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.

## Assumptions

- "Deployer" means the address that executes the constructor, i.e. the constructor's `msg.sender`. On an
  IdentityMD launch that is the ProjectFactory, which then forwards the supply itself (10% to the swarm's
  MerkleDistributor, the pool share to the Uniswap v4 pool, the remainder to the requester's address). This is
  why the constructor takes no owner and no recipient argument: giving the supply to anyone other than the
  factory would break the launch flows.
- The brief asks for no transfer rules (no tax, burn, reflections, vesting or governance), so none are
  implemented. Adding any later would need a new contract: this one is not upgradeable by design.
- Decimals are 18, the ERC-20 default the brief specifies.
- The contract name `HamsterToken` is 12 characters, within the manifest's 32-character limit, and is
  independent of the token's `name()`/`symbol()`.

## Launch parameters (decided by the launch, recorded here for reference)

These are supplied by the launch and the manifest step, not by this repository. Nothing here needs to be set.

| Parameter | Value |
| --- | --- |
| Chain | Ethereum mainnet (chain id 1) |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Pool fee | 12500 (1.25%) |
| Tick spacing | 60 |
| `token.totalSupply` for the manifest | `1000000000000000000000000000` |
| `token.decimals` for the manifest | `18` |
| `token.constructorArgs` for the manifest | `[]` |
| Economics | `poolBps` 5000, `initialMarketCapWei` 2500 IMD (`2500000000000000000000`), `remainderTo` `0x3ed212257958724579f13b3dba74a07ac6007903` |

Resulting distribution at launch (performed by the factory, not by this contract): 10% to the swarm's
distributor, 50% seeds the IMD/HAMSTER pool single-sided at a 2,500 IMD opening market cap for the whole supply,
and the remaining 40% goes to `remainderTo`.

The manifest (`launch.json`) is written by the manifest step after this work is accepted. This repository
intentionally does not contain one.

## After launch

There is nothing to configure. The token has no owner-settable values, no setters and no admin functions.

## Operational responsibilities

- **Key custody:** whoever deploys outside the IdentityMD launch receives the entire supply at the deploying
  address and is solely responsible for it. There is no recovery, freeze or clawback mechanism.
- **No admin:** nobody can pause transfers, blacklist holders, seize balances, change metadata or mint. Holders
  are responsible for their own keys and approvals. Avoid granting unlimited allowances to contracts you do not
  trust.
- **Supply accounting:** `totalSupply()` only ever decreases if holders send tokens to unrecoverable addresses;
  the contract itself offers no burn function.
- **Explorer verification:** verify the source on Etherscan after deployment (`forge verify-contract` with
  compiler 0.8.26, optimizer 200 runs, `bytecode_hash = none`, `cbor_metadata = false`). This belongs to the
  launch's deployer, not to this task.
- **Audit status:** tests passing is not an audit. The token is a thin wrapper over OpenZeppelin's audited ERC20
  with no added logic, which keeps the surface minimal, but an independent adversarial review is still
  recommended before release.

## Repository layout

```
foundry.toml                 Compiler pins and build settings (solc 0.8.26, bytecode_hash none)
remappings.txt               forge-std and @openzeppelin/contracts remappings into lib/
src/HamsterToken.sol         The token
script/DeployHamsterToken.s.sol  Reference deploy script (not used by the IdentityMD launch)
test/HamsterToken.t.sol      Unit and fuzz tests
test/DeployHamsterToken.t.sol    Deploy-script test (calls deploy() directly, reads no environment)
lib/forge-std/               forge-std v1.11.0 (vendored, plain files)
lib/openzeppelin-contracts/  OpenZeppelin Contracts v5.4.0, ERC20 subset (vendored, plain files)
```

## Building and testing

```
forge build
forge test
forge fmt --check
```

Tests read no environment variables, depend on no network and pass in any order. The fuzz tests pass with the
verifier's seed:

```
FOUNDRY_FUZZ_SEED=0x45a2fcb490c8d856ac2203f7b7a55ad913a4f6ab4b094a3755e7c5ed1d1e5d92 forge test
```

### What the tests cover

- Metadata and supply constants; the constructor mints exactly the supply to `msg.sender` and emits both events.
- Deployment through a CREATE2 factory probe leaves the whole supply with the factory, which can then pay it out.
- Transfer, approve and transferFrom success paths, including whole-balance transfers, zero-amount transfers
  and infinite allowances.
- Failure paths: insufficient balance (by exactly one unit as well), zero-address receiver and spender,
  missing and insufficient allowance.
- Absence of any mint, owner, pause, blacklist, upgrade or burnFrom entry point from both a stranger and the
  deployer; supply and balances unchanged afterwards.
- Nobody can pull a holder's balance without allowance, and the holder can still transfer afterwards.
- The contract rejects ether and its runtime has no DELEGATECALL, CALLCODE or SELFDESTRUCT.
- Fuzz: supply conservation on transfers, reverts above balance and above allowance, allowance accounting, and
  every deployer address receiving the full supply.

## Dependencies

Vendored as ordinary files under `lib/` (no git submodules), with their licences:

- forge-std v1.11.0 (MIT / Apache-2.0)
- OpenZeppelin Contracts v5.4.0 (MIT): `token/ERC20/ERC20.sol`, `token/ERC20/IERC20.sol`,
  `token/ERC20/extensions/IERC20Metadata.sol`, `utils/Context.sol`, `interfaces/draft-IERC6093.sol`
