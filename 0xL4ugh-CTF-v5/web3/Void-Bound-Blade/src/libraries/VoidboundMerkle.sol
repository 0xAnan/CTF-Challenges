// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVoidboundSanctum} from "src/interfaces/IVoidboundSanctum.sol";

library VoidboundMerkle {
    // === World tree layout (no bug) ===
    uint256 public constant WORLD_NUM_ELEMENTS = 4;
    uint256 public constant WORLD_TREE_HEIGHT = 3;
    uint256 public constant WORLD_BLADES_INDEX = 3;
    uint256 public constant WORLD_RELICS_INDEX = 2;

    // === Subtree sizes (no bug) ===
    uint256 public constant BLADES_NUM_ELEMENTS = 128;
    uint256 public constant BLADES_TREE_HEIGHT = 8;
    uint256 public constant RELICS_NUM_ELEMENTS = 64;
    uint256 public constant RELICS_TREE_HEIGHT = 7;

    // === Leaf widths (no bug) ===
    uint256 public constant BLADE_NUM_ELEMENTS = 4;
    uint256 public constant RELIC_BLADE_NUM_ELEMENTS = 7;

    // === Blade proof (bug: XOR path crosses subtrees) ===
    function proveBlade(
        IVoidboundSanctum.Blade memory blade,
        bytes32 root,
        bytes32[] memory proof
    ) internal pure returns (bool) {
        uint256 path = (WORLD_BLADES_INDEX << (BLADES_TREE_HEIGHT - 1)) ^ blade.id; // Bug: XOR flips the world index when id >= 128.
        return _merkleProof(root, merkleizeBlade(blade), path, proof); // Verify proof against computed path.
    }

    // === Relic proof (bug: XOR path crosses subtrees) ===
    function proveRelic(
        IVoidboundSanctum.Relic memory relic,
        bytes32 root,
        bytes32[] memory proof
    ) internal pure returns (bool) {
        uint256 path = (WORLD_RELICS_INDEX << (RELICS_TREE_HEIGHT - 1)) ^ relic.id; // XOR is harmless for relic ids < 64.
        return _merkleProof(root, merkleizeRelic(relic), path, proof); // Verify proof against computed path.
    }

    // === World merkleization (no bug) ===
    function merkleizeSanctum(
        string memory sanctumName,
        uint256 clanCount,
        IVoidboundSanctum.Blade[] storage blades,
        IVoidboundSanctum.Relic[] storage relics
    ) internal view returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](WORLD_NUM_ELEMENTS); // Fixed world layout.
        hashed[0] = keccak256(abi.encode(sanctumName)); // Leaf 0: name.
        hashed[1] = keccak256(abi.encode(clanCount)); // Leaf 1: clan count.
        hashed[2] = merkleizeRelics(relics); // Leaf 2: relic subtree.
        hashed[3] = merkleizeBlades(blades); // Leaf 3: blade subtree.
        return merkleize(hashed); // Root of the world.
    }

    // === Blade subtree merkleization (no bug) ===
    function merkleizeBlades(
        IVoidboundSanctum.Blade[] storage blades
    ) internal view returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](BLADES_NUM_ELEMENTS); // Fixed-size blades tree.
        for (uint256 i; i < blades.length && i < BLADES_NUM_ELEMENTS; i++) {
            hashed[i] = merkleizeBlade(blades[i]); // Leaf i: blade i.
        }
        return merkleize(hashed); // Root of the blades subtree.
    }

    // === Relic subtree merkleization (no bug) ===
    function merkleizeRelics(
        IVoidboundSanctum.Relic[] storage relics
    ) internal view returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](RELICS_NUM_ELEMENTS); // Fixed-size relics tree.
        for (uint256 i; i < relics.length; i++) {
            hashed[i] = merkleizeRelic(relics[i]); // Leaf i: relic i.
        }
        return merkleize(hashed); // Root of the relics subtree.
    }

    // === Blade leaf merkleization (no bug) ===
    function merkleizeBlade(
        IVoidboundSanctum.Blade memory blade
    ) internal pure returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](BLADE_NUM_ELEMENTS); // Four fields per blade.
        hashed[0] = keccak256(abi.encode(blade.id)); // Field 0: id.
        hashed[1] = keccak256(abi.encode(blade.edge)); // Field 1: edge.
        hashed[2] = keccak256(abi.encode(blade.tempo)); // Field 2: tempo.
        hashed[3] = keccak256(abi.encode(blade.roninId)); // Field 3: ronin id.
        return merkleize(hashed); // Leaf root.
    }

    // === Relic leaf merkleization (no bug) ===
    function merkleizeRelic(
        IVoidboundSanctum.Relic memory relic
    ) internal pure returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](RELIC_BLADE_NUM_ELEMENTS); // Seven fields per relic.
        hashed[0] = keccak256(abi.encode(relic.id)); // Field 0: id.
        hashed[1] = keccak256(abi.encode(relic.title)); // Field 1: title.
        hashed[2] = keccak256(abi.encode(relic.myth)); // Field 2: myth.
        hashed[3] = keccak256(abi.encode(relic.temper)); // Field 3: temper.
        hashed[4] = keccak256(abi.encode(relic.attunement)); // Field 4: attunement.
        hashed[5] = keccak256(abi.encode(relic.sigil)); // Field 5: sigil.
        hashed[6] = keccak256(abi.encode(relic.isSealed)); // Field 6: sealed flag.
        return merkleize(hashed); // Leaf root.
    }


    // === Generic merkleizer (no bug) ===
    function merkleize(bytes32[] memory input) internal pure returns (bytes32) {
        uint256 n = _upperPow2(input.length); // Round up to a power of two.
        bytes32[] memory cache = new bytes32[](n); // Working buffer for in-place hashing.
        for (uint256 i = 0; i < input.length; i++) {
            cache[i] = input[i]; // Copy leaves; missing leaves stay zero.
        }
        n /= 2;
        while (n > 0) {
            for (uint256 i = 0; i < n; i++) {
                (bytes32 l, bytes32 r) = (cache[2 * i], cache[2 * i + 1]);
                if (r == bytes32(0)) {
                    if (l == bytes32(0)) {
                        cache[i] = bytes32(0);
                    } else {
                        cache[i] = keccak256(abi.encodePacked(l, l)); // Mirror left when right is empty.
                    }
                } else {
                    cache[i] = keccak256(abi.encodePacked(l, r)); // Standard node hash.
                }
            }
            n /= 2;
        }
        return cache[0]; // Root.
    }

    // === Utility: next power of two (no bug) ===
    function _upperPow2(uint256 n) private pure returns (uint256 x) {
        x = 1; // Start at 2^0.
        while (n > x) {
            x <<= 1; // Shift until n fits.
        }
    }

    // === Proof verification (no bug; relies on path correctness) ===
    function _merkleProof(
        bytes32 root,
        bytes32 leaf,
        uint256 path,
        bytes32[] memory proof
    ) private pure returns (bool) {
        bytes32 hashed = leaf; // Start from leaf.
        for (uint256 i; i < proof.length; i++) {
            if (path % 2 == 0) {
                hashed = keccak256(abi.encodePacked(hashed, proof[i])); // Leaf/node is on the left.
            } else {
                hashed = keccak256(abi.encodePacked(proof[i], hashed)); // Leaf/node is on the right.
            }
            path >>= 1; // Move to the next level.
        }
        return root == hashed; // Proof is valid if final hash matches root.
    }
}
