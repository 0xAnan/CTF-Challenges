# CTF Challenges by 0xAnan

Challenges I authored, with source and a solver for each. Writeups are on my blog: [anan.rocks](https://anan.rocks/My-Challenges).

Each challenge is a self-contained `.zip` you can download and run right away. It bundles the challenge contracts, the solver, the test suite, and a vendored `forge-std` so there's no install step. The deployment side (contract-factory backend, flags, keys) is not included, only what you need to understand and reproduce the exploit.

## Index

| Event | Challenge | Category | Bug class | Writeup |
|---|---|---|---|---|
| 0xL4ugh CTF v5 (2025) | [House of Illusions](0xL4ugh-CTF-v5/web3/House-of-Illusions) | web3 | proxy upgrade + calldata overlap | [read](https://anan.rocks/My-Challenges/0xL4ugh-CTF-v5/web3/House-of-Illusions) |
| 0xL4ugh CTF v5 (2025) | [Void Bound Blade](0xL4ugh-CTF-v5/web3/Void-Bound-Blade) | web3 | gate bypass + reentrancy + Merkle type-confusion | [read](https://anan.rocks/My-Challenges/0xL4ugh-CTF-v5/web3/Void-Bound-Blade) |

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
forge test
```

Deps are vendored, so no install is needed. To run the solver against a live instance, see that challenge's own README.
