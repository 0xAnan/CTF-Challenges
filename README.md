# CTF Challenges — by 0xAnan

Challenges I authored, with source and a working solver for each. Full writeups live on my blog: **[anan.rocks](https://anan.rocks/My-Challenges)**.

Each challenge folder ships the challenge contracts, the reference **solver**, and the test suite. The deployment/infra (contract-factory backend, flags, keys) is intentionally **not** included — only what you need to understand and reproduce the exploit.

## Index

| Event | Challenge | Category | Bug class | Solver | Writeup |
|---|---|---|---|---|---|
| 0xL4ugh CTF v5 (2025) | [House of Illusions](0xL4ugh-CTF-v5/web3/House-of-Illusions) | web3 | proxy upgrade + calldata overlap | ✅ verified | [read](https://anan.rocks/My-Challenges/0xL4ugh-CTF-v5/web3/House-of-Illusions) |
| 0xL4ugh CTF v5 (2025) | [Void Bound Blade](0xL4ugh-CTF-v5/web3/Void-Bound-Blade) | web3 | gate bypass + reentrancy + Merkle type-confusion | ✅ verified | [read](https://anan.rocks/My-Challenges/0xL4ugh-CTF-v5/web3/Void-Bound-Blade) |

> **✅ verified** — every solver is confirmed against the challenge's `isSolved()` on a local node (`false → true`), and each `test/` suite passes (8/8 each).

## Layout

```
0xL4ugh-CTF-v5/
└── web3/
    ├── House-of-Illusions/   # MirrorProxy + IllusionHouse — claim the Curator role
    └── Void-Bound-Blade/     # VoidboundSanctum — slay the 1e12-HP Void Shogun
```

Each challenge is an independent [Foundry](https://book.getfoundry.sh/) project.

## Running a solver

Deps are git submodules, so clone recursively:

```bash
git clone --recursive https://github.com/0xAnan/CTF-Challenges
# or, after a plain clone:
git submodule update --init --recursive
```

Then, inside a challenge folder:

```bash
forge test            # run the suite (proves the exploit)
```

To run the reference solver against a live instance, see that challenge's own README.

---
`0xANAN / 攻` · Breaking, learning, documenting
