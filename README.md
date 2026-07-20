# CTF Challenges — by 0xAnan

Challenges I authored, with source and a working solver for each. Full writeups live on my blog: **[anan.rocks](https://anan.rocks/My-Challenges)**.

Each challenge is a **self-contained `.zip`** you can download and run immediately — it bundles the challenge contracts, the reference **solver**, the test suite, and vendored `forge-std` (no install step). The deployment/infra (contract-factory backend, flags, keys) is intentionally **not** included — only what you need to understand and reproduce the exploit.

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
    ├── House-of-Illusions/   # README + House-of-Illusions.zip
    └── Void-Bound-Blade/     # README + Void-Bound-Blade.zip
```

Each `.zip` unpacks to an independent [Foundry](https://book.getfoundry.sh/) project.

## Running a challenge

Download the challenge `.zip` from its folder, then:

```bash
unzip House-of-Illusions.zip -d House-of-Illusions
cd House-of-Illusions
forge test            # runs the suite — proves the exploit. deps are vendored, no install needed.
```

To run the reference solver against a live instance, see that challenge's own README.

---
`0xANAN / 攻` · Breaking, learning, documenting
