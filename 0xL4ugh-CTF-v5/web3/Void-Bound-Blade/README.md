# Void Bound Blade

- **Event:** 0xL4ugh CTF v5 (2025)
- **Category:** web3, Solidity / game
- **Author:** 0xAnan
- **Writeup:** https://anan.rocks/My-Challenges/0xL4ugh-CTF-v5/web3/Void-Bound-Blade

> *The Void Shogun, 1,000,000,000,000 HP, guards the sanctum. The gates are sealed to outsiders. Prove yourself worthy, then strike it down.*

`Setup.isSolved()` returns true once `SANCTUM.getShogun().alive == false`.

## The bugs

Three chained flaws:

1. Torii gate bypass. `shadowTorii` checks a selector at a *fixed* calldata offset. Crafted calldata places a decoy selector there while the real payload calls `enterSanctum`. Done from a constructor (`extcodesize(msg.sender) == 0`) it whitelists `tx.origin`.
2. Forge reentrancy. `forgeBladeRite` calls into a herald before finalizing, so an `onForgeStamp` callback re-enters to batch-mint blades cheaply.
3. Merkle type-confusion. An XOR path in `bindBlade` lets a blade's `id` steer into the *relic* subtree, so a forged proof overwrites relic-backed stats. Pump attunement, forge the winning blade, `duelShogun`.

Proof construction and the exact stat math are in the writeup.

## Files

Inside [`Void-Bound-Blade.zip`](Void-Bound-Blade.zip):

| Path | What |
|---|---|
| `src/VoidboundSanctum.sol` | vulnerable game contract |
| `src/libraries/VoidboundMerkle.sol` | Merkle constants |
| `src/interfaces/IVoidboundSanctum.sol` | struct and interface types |
| `src/Setup.sol` | challenge deployer and `isSolved()` |
| `script/Deploy.s.sol` | deploys an instance |
| `script/Solve.s.sol` | the solver (gate wraith, forge herald, proof builder) |
| `test/VoidboundSanctum.t.sol` | mechanics and negative tests |

## Run

```bash
unzip Void-Bound-Blade.zip -d Void-Bound-Blade && cd Void-Bound-Blade
forge test -vv
```

Against a live instance (local node shown):

```bash
# start a node
anvil

# deploy (PLAYER = your address)
PLAYER=$PLAYER forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 --private-key $PK --broadcast

# solve. SANCTUM is the VoidboundSanctum address, from challenge.SANCTUM()
SANCTUM=<sanctum-address> forge script script/Solve.s.sol:Solve \
  --rpc-url http://127.0.0.1:8545 --private-key $PK --broadcast

# check
cast call <challenge-address> "isSolved()(bool)" --rpc-url http://127.0.0.1:8545
```
