// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {VoidboundSanctum} from "src/VoidboundSanctum.sol";
import {IVoidboundSanctum} from "src/interfaces/IVoidboundSanctum.sol";
import {VoidboundMerkle} from "src/libraries/VoidboundMerkle.sol";

// Helper to pass the torii gate by calling performKata from a constructor.
contract ToriiWraith {
    constructor(VoidboundSanctum sanctum) {
        bytes4 decoy = bytes4(keccak256("normalFunction()"));
        bytes4 enterSel = sanctum.enterSanctum.selector;
        bytes memory callData = abi.encodePacked(
            sanctum.performKata.selector,
            bytes32(uint256(0x60)),
            bytes32(0),
            bytes32(decoy),
            bytes32(uint256(4)),
            bytes32(enterSel)
        );
        (bool success, ) = address(sanctum).call(callData);
        require(success, "GATE_FAIL");
    }
}

// Naive constructor-only call that does not craft calldata (expected to fail).
contract ToriiPlain {
    constructor(VoidboundSanctum sanctum) {
        bytes memory payload = abi.encodeWithSelector(sanctum.enterSanctum.selector);
        bytes memory callData = abi.encodeWithSelector(sanctum.performKata.selector, payload);
        (bool success, bytes memory data) = address(sanctum).call(callData);
        if (!success) {
            assembly {
                revert(add(data, 32), mload(data))
            }
        }
    }
}

contract VoidboundSanctumTest is Test {
    VoidboundSanctum private sanctum;
    address private player = address(0xBEEF);

    function setUp() public {
        sanctum = new VoidboundSanctum();
        vm.startPrank(player, player);
        new ToriiWraith(sanctum);
        vm.stopPrank();
    }

    function testAwakenMintsStarterAtZero() public {
        vm.startPrank(player);
        sanctum.awakenRonin();

        IVoidboundSanctum.Ronin memory ronin = _ronin(player);
        assertEq(ronin.equippedBladeId, 0);

        IVoidboundSanctum.Blade memory blade0 = sanctum.getBlade(0);
        assertEq(blade0.id, 0);
        assertEq(sanctum.bladeSlotById(0), 1);
        assertEq(sanctum.bladeOwner(0), player);
        vm.stopPrank();
    }

    function testToriiPlainConstructorFails() public {
        vm.startPrank(player, player);
        vm.expectRevert(bytes("THE_GATE_REFUSES"));
        new ToriiPlain(sanctum);
        vm.stopPrank();
    }

    function testForgeIdsFollowArrayOrder() public {
        vm.startPrank(player);
        sanctum.awakenRonin();
        sanctum.pledgeClan(0);

        uint256 forgedId = sanctum.forgeBlade(2, 3);
        assertEq(forgedId, 1);

        IVoidboundSanctum.Blade memory blade1 = sanctum.getBlade(1);
        assertEq(blade1.id, 1);
        assertEq(sanctum.bladeSlotById(1), 2);
        assertEq(sanctum.bladeOwner(1), player);
        vm.stopPrank();
    }

    function testMeditateIncreasesStats() public {
        vm.startPrank(player);
        sanctum.awakenRonin();

        IVoidboundSanctum.Ronin memory before = _ronin(player);
        sanctum.meditate();
        IVoidboundSanctum.Ronin memory afterRonin = _ronin(player);

        assertEq(uint256(afterRonin.level), uint256(before.level) + 1);
        assertEq(afterRonin.hp, before.hp + sanctum.MEDITATION_HP_BONUS());
        vm.stopPrank();
    }

    function testAwakenAfterDeathCreatesNewRonin() public {
        vm.startPrank(player);
        sanctum.awakenRonin();

        IVoidboundSanctum.Ronin memory first = _ronin(player);
        sanctum.duelShogun();
        IVoidboundSanctum.Ronin memory fallen = _ronin(player);
        assertEq(fallen.hp, 0);

        sanctum.awakenRonin();
        IVoidboundSanctum.Ronin memory reborn = _ronin(player);
        assertEq(reborn.id, first.id + 1);
        assertEq(reborn.level, 1);
        assertEq(reborn.hp, sanctum.RONIN_BASE_HP());
        assertEq(reborn.equippedBladeId, first.equippedBladeId + 1);
        vm.stopPrank();
    }

    function testEquipAndDuelDoesNotWin() public {
        vm.startPrank(player);
        sanctum.awakenRonin();
        sanctum.pledgeClan(0);

        uint256 forgedId = sanctum.forgeBlade(5, 4);
        IVoidboundSanctum.Blade memory blade = sanctum.getBlade(forgedId);
        bytes32[] memory proof = _buildBladeProof(forgedId);
        sanctum.bindBlade(blade, proof);

        IVoidboundSanctum.VoidShogun memory before = sanctum.getShogun();
        sanctum.duelShogun();
        IVoidboundSanctum.VoidShogun memory afterShogun = sanctum.getShogun();

        assertTrue(afterShogun.alive);
        assertLt(afterShogun.hp, before.hp);

        IVoidboundSanctum.Ronin memory ronin = _ronin(player);
        assertEq(ronin.equippedBladeId, forgedId);
        assertEq(ronin.hp, beforeHpAfterStrike());
        vm.stopPrank();
    }

    function testBindBladeWithHonestProof() public {
        vm.startPrank(player);
        sanctum.awakenRonin();
        sanctum.pledgeClan(0);

        uint256 forgedId = sanctum.forgeBlade(2, 3);
        IVoidboundSanctum.Blade memory blade = sanctum.getBlade(forgedId);
        bytes32[] memory proof = _buildBladeProof(forgedId);

        sanctum.bindBlade(blade, proof);

        IVoidboundSanctum.Blade memory stored = sanctum.getBlade(forgedId);
        assertEq(stored.edge, blade.edge);
        assertEq(stored.tempo, blade.tempo);
        vm.stopPrank();
    }

    function testBindBladeRejectsBadProof() public {
        vm.startPrank(player);
        sanctum.awakenRonin();
        sanctum.pledgeClan(0);

        uint256 forgedId = sanctum.forgeBlade(2, 3);
        IVoidboundSanctum.Blade memory blade = sanctum.getBlade(forgedId);
        bytes32[] memory proof = _buildBladeProof(forgedId);

        blade.edge += 1;
        vm.expectRevert(bytes("INVALID_BLADE_PROOF"));
        sanctum.bindBlade(blade, proof);
        vm.stopPrank();
    }

    function beforeHpAfterStrike() private view returns (uint256) {
        IVoidboundSanctum.VoidShogun memory shogun = sanctum.getShogun();
        uint256 baseHp = sanctum.RONIN_BASE_HP();
        if (shogun.strikeDamage >= baseHp) {
            return 0;
        }
        return baseHp - shogun.strikeDamage;
    }

    function _ronin(address who) private view returns (IVoidboundSanctum.Ronin memory ronin) {
        (uint256 id, uint256 hp, uint8 level, uint256 equippedBladeId) = sanctum.roninOf(who);
        ronin = IVoidboundSanctum.Ronin({
            id: id,
            hp: hp,
            level: level,
            equippedBladeId: equippedBladeId
        });
    }

    function _buildBladeProof(uint256 bladeIndex) private view returns (bytes32[] memory proof) {
        bytes32[] memory bladeLeaves = new bytes32[](VoidboundMerkle.BLADES_NUM_ELEMENTS);
        uint256 count = sanctum.getBladeCount();
        if (count > VoidboundMerkle.BLADES_NUM_ELEMENTS) {
            count = VoidboundMerkle.BLADES_NUM_ELEMENTS;
        }
        for (uint256 i; i < count; i++) {
            bladeLeaves[i] = _merkleizeBlade(sanctum.getBlade(i));
        }
        bytes32[] memory bladeProof = _buildSubtreeProof(bladeLeaves, bladeIndex);

        bytes32 relicsRoot = _relicsRoot();
        bytes32 leftWorld = _hash(
            keccak256(abi.encode(sanctum.sanctumName())),
            keccak256(abi.encode(uint256(1)))
        );

        proof = new bytes32[](bladeProof.length + 2);
        for (uint256 i; i < bladeProof.length; i++) {
            proof[i] = bladeProof[i];
        }
        proof[bladeProof.length] = relicsRoot;
        proof[bladeProof.length + 1] = leftWorld;
    }

    function _relicsRoot() private view returns (bytes32 root) {
        bytes32[] memory relicLeaves = new bytes32[](VoidboundMerkle.RELICS_NUM_ELEMENTS);
        uint256 count = sanctum.getRelicCount();
        for (uint256 i; i < count; i++) {
            relicLeaves[i] = _merkleizeRelic(sanctum.getRelic(i));
        }
        root = _merkleize(relicLeaves);
    }

    function _buildSubtreeProof(
        bytes32[] memory leaves,
        uint256 index
    ) private pure returns (bytes32[] memory proof) {
        uint256 n = _upperPow2(leaves.length);
        bytes32[] memory level = new bytes32[](n);
        for (uint256 i; i < leaves.length; i++) {
            level[i] = leaves[i];
        }

        proof = new bytes32[](_log2(n));
        uint256 idx = index;
        uint256 size = n;
        uint256 proofIndex = 0;
        while (size > 1) {
            uint256 sibling = idx ^ 1;
            bytes32 siblingHash = level[sibling];
            if (siblingHash == bytes32(0) && idx % 2 == 0) {
                // Mirror-left rule: if right is empty, the proof must use the left hash.
                siblingHash = level[idx];
            }
            proof[proofIndex++] = siblingHash;
            for (uint256 i; i < size; i += 2) {
                bytes32 left = level[i];
                bytes32 right = level[i + 1];
                if (right == bytes32(0)) {
                    if (left == bytes32(0)) {
                        level[i / 2] = bytes32(0);
                    } else {
                        level[i / 2] = keccak256(abi.encodePacked(left, left));
                    }
                } else {
                    level[i / 2] = keccak256(abi.encodePacked(left, right));
                }
            }
            idx >>= 1;
            size >>= 1;
        }
    }

    function _merkleize(bytes32[] memory input) private pure returns (bytes32) {
        uint256 n = _upperPow2(input.length);
        bytes32[] memory cache = new bytes32[](n);
        for (uint256 i; i < input.length; i++) {
            cache[i] = input[i];
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
                        cache[i] = keccak256(abi.encodePacked(left, left));
                    }
                } else {
                    cache[i] = keccak256(abi.encodePacked(left, right));
                }
            }
            n /= 2;
        }
        return cache[0];
    }

    function _merkleizeBlade(
        IVoidboundSanctum.Blade memory blade
    ) private pure returns (bytes32 root) {
        bytes32 h0 = keccak256(abi.encode(blade.id));
        bytes32 h1 = keccak256(abi.encode(blade.edge));
        bytes32 h2 = keccak256(abi.encode(blade.tempo));
        bytes32 h3 = keccak256(abi.encode(blade.roninId));
        root = _hash(_hash(h0, h1), _hash(h2, h3));
    }

    function _merkleizeRelic(
        IVoidboundSanctum.Relic memory relic
    ) private pure returns (bytes32 root) {
        bytes32 h0 = keccak256(abi.encode(relic.id));
        bytes32 h1 = keccak256(abi.encode(relic.title));
        bytes32 h2 = keccak256(abi.encode(relic.myth));
        bytes32 h3 = keccak256(abi.encode(relic.temper));
        bytes32 h4 = keccak256(abi.encode(relic.attunement));
        bytes32 h5 = keccak256(abi.encode(relic.sigil));
        bytes32 h6 = keccak256(abi.encode(relic.isSealed));
        bytes32 left = _hash(_hash(h0, h1), _hash(h2, h3));
        bytes32 right = _hash(_hash(h4, h5), _hash(h6, h6));
        root = _hash(left, right);
    }

    function _upperPow2(uint256 n) private pure returns (uint256 x) {
        x = 1;
        while (n > x) {
            x <<= 1;
        }
    }

    function _log2(uint256 n) private pure returns (uint256 x) {
        while (n > 1) {
            n >>= 1;
            x += 1;
        }
    }

    function _hash(bytes32 left, bytes32 right) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(left, right));
    }
}
