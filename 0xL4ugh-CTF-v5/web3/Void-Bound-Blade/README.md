# Void Bound Blade

- **Event:** 0xL4ugh CTF v5 (2025)
- **Category:** web3 · Solidity / game
- **Author:** 0xAnan
- **Full writeup:** https://anan.rocks/My-Challenges/0xL4ugh-CTF-v5/web3/Void-Bound-Blade

> *The Void Shogun — 1,000,000,000,000 HP — guards the sanctum. The gates are sealed to outsiders. Prove yourself worthy, then strike it down.*

`Setup.isSolved()` returns true once `SANCTUM.getShogun().alive == false`.

## The bugs (short)

Three chained flaws:

1. **Torii gate bypass** — `shadowTorii` checks a selector at a *fixed* calldata offset. Crafted calldata places a decoy selector there while the real payload calls `enterSanctum`; done from a constructor (`extcodesize(msg.sender) == 0`) it whitelists `tx.origin`.
2. **Forge reentrancy** — `forgeBladeRite` calls into a herald before finalizing, so an `onForgeStamp` callback re-enters to batch-mint blades cheaply.
3. **Merkle type-confusion** — an XOR path in `bindBlade` lets a blade's `id` steer into the *relic* subtree, so a forged proof overwrites relic-backed stats. Pump attunement, forge the winning blade, `duelShogun`.

Proof construction and the exact stat math are in the writeup.

## Files

| Path | What |
|---|---|
| `src/VoidboundSanctum.sol` | vulnerable game contract |
| `src/libraries/VoidboundMerkle.sol` | Merkle constants |
| `src/interfaces/IVoidboundSanctum.sol` | struct/interface types |
| `src/Setup.sol` | challenge deployer + `isSolved()` |
| `script/Deploy.s.sol` | deploys an instance |
| `script/Solve.s.sol` | **the solver** (gate wraith + forge herald + proof builder) |
| `test/VoidboundSanctum.t.sol` | mechanics + negative tests (8) |

## Run

```bash
forge test -vv          # 8/8
```

Against a live instance (local node shown):

```bash
# 1. start a node
anvil

# 2. deploy (PLAYER = your address)
PLAYER=$PLAYER forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 --private-key $PK --broadcast

# 3. solve — SANCTUM is the VoidboundSanctum address (challenge.SANCTUM())
SANCTUM=<sanctum-address> forge script script/Solve.s.sol:Solve \
  --rpc-url http://127.0.0.1:8545 --private-key $PK --broadcast

# 4. check
cast call <challenge-address> "isSolved()(bool)" --rpc-url http://127.0.0.1:8545   # -> true
```

✅ Verified: `isSolved()` flips `false → true`.
