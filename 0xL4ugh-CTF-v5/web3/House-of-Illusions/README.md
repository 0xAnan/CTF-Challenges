# House of Illusions

- **Event:** 0xL4ugh CTF v5 (2025)
- **Category:** web3 · Solidity / proxy
- **Author:** 0xAnan
- **Full writeup:** https://anan.rocks/My-Challenges/0xL4ugh-CTF-v5/web3/House-of-Illusions

> *A mirror-proxy manor that rewrites what you think is real. You're admitted as a Visitor, but only a Curator may command the house. Claim the Curator role for your address.*

`Setup.isSolved()` returns true once `roles(VISITOR) == Role.Curator`.

## The bug (short)

Two pieces combine:

1. **`MirrorProxy.reframe`** lets the visitor point the proxy at a new implementation, guarded by a code-hash check that only compares *runtime* logic — a comment-only re-derivation of the house passes it.
2. **`IllusionHouse.admit`** validates its `sigil` argument two different ways in the same call: hand-sliced `msg.data[...]` windows *and* `abi.decode`. A crafted calldata layout satisfies the sigil/patron checks while smuggling a non-zero `maskRank` into the caller — a masked Visitor, who can then `appointCurator`.

Full derivation of the overlap layout and the proxy guard is in the writeup.

## Files

| Path | What |
|---|---|
| `src/IllusionHouse.sol` | vulnerable implementation |
| `src/MirrorProxy.sol` | upgradeable mirror proxy |
| `src/Setup.sol` | challenge deployer + `isSolved()` |
| `src/solution/IllusionHouse.sol` | reframed implementation used by the exploit |
| `script/HouseOfIllusions.s.sol` | **the solver** |
| `test/HouseOfIllusions.t.sol` | full-flow + negative tests (8) |

## Run

```bash
forge test -vv          # proves the exploit (8/8)
```

Against a live instance (local node shown):

```bash
# 1. start a node
anvil

# 2. deploy the challenge (visitor = your address)
forge create src/Setup.sol:Setup \
  --rpc-url http://127.0.0.1:8545 --private-key $PK \
  --broadcast --value 1ether --constructor-args $PLAYER

# 3. run the solver
CHALLENGE=<setup-address> PRIVATE_KEY=$PK \
  forge script script/HouseOfIllusions.s.sol:HouseOfIllusionsScript \
  --rpc-url http://127.0.0.1:8545 --broadcast

# 4. check
cast call <setup-address> "isSolved()(bool)" --rpc-url http://127.0.0.1:8545   # -> true
```

✅ Verified: `isSolved()` flips `false → true`.
