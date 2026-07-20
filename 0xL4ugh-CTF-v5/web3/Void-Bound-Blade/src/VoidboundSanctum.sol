// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVoidboundSanctum} from "src/interfaces/IVoidboundSanctum.sol";
import {VoidboundMerkle} from "src/libraries/VoidboundMerkle.sol";

// === External forge hook (intentional re-entrancy surface) ===
// Used by forgeBladeRite to allow a herald contract to mint multiple blades
// in a single transaction; this is a deliberate "game convenience" hook.
interface IForgeHerald {
    // Called during forgeBladeRite; can re-enter via forgeBladeViaHerald.
    function onForgeStamp(address caller, uint256 lastId) external;
}

contract VoidboundSanctum is IVoidboundSanctum {
    // === Game tuning constants (no bug) ===
    uint256 public constant MAX_BLADE_EDGE = 100; // Cap for blade damage.
    uint256 public constant MAX_BLADE_TEMPO = 10; // Cap for blade speed.
    uint256 public constant RONIN_BASE_HP = 10_000; // Base HP on awaken.
    uint256 public constant MEDITATION_HP_BONUS = 100; // HP gained per meditate.
    bytes4 public constant FORBIDDEN_SELECTOR = bytes4(keccak256("enterSanctum()")); // Forbidden inner selector.

    // === Core world state (no bug) ===
    string public sanctumName; // Display name for the world leaf.
    VoidShogun private shogun; // The boss to defeat.

    // === Clan + ronin state (no bug) ===
    Clan[] public clans; // Fixed list of clans; index is clan id.
    mapping(address => uint256) public clanOf; // 1-based clan id for an account.
    mapping(address => Ronin) public roninOf; // Player character data.
    uint256 public roninCount; // Total ronin minted.
    mapping(address => bool) public whitelist; // Gate: must pass torii to play.
    uint8 private riteDepth; // Mirror rite call depth (reentrancy gate).
    address private riteCaller; // Original caller for rite-only actions.

    // === Gameplay events (no bug) ===
    event RoninAwakened(address indexed account, uint256 indexed roninId, uint256 starterBladeId);
    event RoninMeditated(address indexed account, uint256 level, uint256 hp);
    event BladeForged(address indexed account, uint256 indexed bladeId, uint256 slot);
    event BladeBound(address indexed account, uint256 indexed bladeId, uint256 edge, uint256 tempo);
    event RelicAttuned(address indexed account, uint256 indexed bladeId, uint256 attunement);
    event ShogunDefeated(address indexed account);

    // === Armory storage (bug lives in merkle path, not here) ===
    Blade[] private blades; // On-chain blades, merkleized for proofs.
    Relic[] private relics; // On-chain relics, merkleized for proofs.
    mapping(uint256 => address) public bladeOwner; // Ownership leaf (explicit, not a mapping in proof).
    mapping(uint256 => uint256) public bladeSlotById; // 1-based slot lookup for compact arrays.
    mapping(uint256 => uint256) private starterBladeOfRonin; // Starter blade id per ronin.
    uint256 private nextBladeId; // Auto-incrementing forge id.
    mapping(address => address) public forgeHeraldOf; // Optional herald for re-entrant forging.
    address private heraldCaller; // Cached caller during herald re-entry.
    uint8 private heraldDepth; // Simple re-entry guard for herald flow.

    // === Initialization (no bug) ===
    constructor() {
        sanctumName = "Voidbound Shrine"; // Name is hashed into the world root.
        shogun = VoidShogun({level: 9000, hp: 1_000_000_000_000, alive: true,strikeDamage: 100_000}); // Boss starts alive.
        clans.push(Clan({leader: address(this), hasForge: true, members: 0})); // Pre-seeded forge clan.
        nextBladeId = 0; // Forge ids start at 0 and auto-increment.

        _addRelic("Darkest Eternity", 77, 1312, 1, 3_000_000_000_000, true); // Main relic (attunement target).
        _addRelic("Eclipsebrand", 10, 42, 2, 25, true); // Secondary relic (proof sibling).
    }

    // === Access control (no bug) ===
    modifier onlyClanLeader() {
        uint256 clanId = _clanIdOf(msg.sender);
        require(clans[clanId].leader == msg.sender, "NOT_LEADER"); // Enforce leader-only actions.
        _;
    }

    // Gate: must pass torii before interacting with gameplay.
    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "NOT_WHITELISTED"); // Prevent skipping the kata gate.
        _;
    }

    // Gate: only callable inside a completed mirror rite.
    modifier onlyRite() {
        require(riteDepth == 2, "RITE_NOT_READY"); // Requires the nested rite sequence.
        require(msg.sender == address(this), "ONLY_RITE"); // Must be an internal call.
        _;
    }

    // === Torii gate (bug: checks fixed calldata offset) ===
    modifier shadowTorii(bytes memory _payload) {
        uint256 size;
        address sender = msg.sender;
        assembly {
            size := extcodesize(sender)
        }
        require(size == 0 && sender != tx.origin, "THE_GATE_REFUSES"); // Constructor-only contract caller.

        require(_payload.length >= 4, "THE_GATE_REFUSES"); // Payload must include a selector.

        bytes4 selector;
        assembly {
            selector := calldataload(0x44) // Fixed offset: decoupled from the payload selector.
        }
        require(selector != FORBIDDEN_SELECTOR, "THE_GATE_REFUSES"); // Reject the forbidden selector.
        _;
    }

    // === Gate entrypoint (dispatches payload through torii) ===
    function performKata(bytes memory _payload) public shadowTorii(_payload) {
        (bool success, ) = address(this).call(_payload); // Dispatch arbitrary payload via the torii.
        require(success, "THE_KATA_BREAKS"); // Revert if the inner call fails.
    }

    // === Torii-protected entry (no bug by itself) ===
    function enterSanctum() external {
        require(msg.sender == address(this), "NO_AURA"); // Only callable through performKata.
        whitelist[tx.origin] = true; // Mark the original EOA as whitelisted.
    }

    // === Mirror rite (intentional re-entrancy pattern) ===
    function mirrorRite(bytes memory payload) public {
        if (riteDepth == 0) {
            riteCaller = msg.sender; // Cache the outer caller for rite-only actions.
            riteDepth = 1; // Arm the inner call phase.
            (bool success, ) = address(this).call(payload); // Trigger the inner re-entrant call.
            require(success, "RITE_FAIL"); // Fail if the inner call fails.
            require(riteDepth == 2, "RITE_FAIL"); // Require the inner bounce to happen.
            riteDepth = 0; // Reset rite state on success.
            riteCaller = address(0); // Clear caller cache after completion.
            return;
        }
        if (riteDepth == 1) {
            require(msg.sender == address(this), "RITE_FAIL"); // Only the self-call can advance.
            riteDepth = 2; // Signal rite completion to the outer frame.
            return;
        }
        revert("RITE_FAIL");
    }

    // === Single attune helper (no bug; uses mirrorRite gate) ===
    function voidAttune(uint256 bladeId) external {
        mirrorRite(""); // Must pass the rite gate to call attuneRelic.
        this.attuneRelic(bladeId); // External call so onlyRite applies.
    }

    // === Batch attune helper (no bug; reduces tx count) ===
    function voidAttuneBatch(uint256[] calldata bladeIds) external {
        mirrorRite(""); // Gate for the whole batch.
        for (uint256 i = 0; i < bladeIds.length; i++) {
            _equipForRite(riteCaller, bladeIds[i]); // Equip using cached caller.
            this.attuneRelic(bladeIds[i]); // Consume each blade inside the rite.
        }
    }

    // === Join a clan (no bug) ===
    function pledgeClan(uint256 clanId) external onlyWhitelisted {
        require(clanOf[msg.sender] == 0, "ALREADY_IN_CLAN"); // Only join once.
        require(clanId < clans.length, "UNKNOWN_CLAN"); // Prevent out-of-range clans.
        clanOf[msg.sender] = clanId + 1; // Store as 1-based to differentiate "unset".
        clans[clanId].members++; // Track membership count.
    }

    // === Create a ronin and starter blade (no bug) ===
    function awakenRonin() external onlyWhitelisted {
        require(roninOf[msg.sender].hp <= 0, "RONIN_EXISTS"); // One ronin per account.
        uint256 id = roninCount; // Next ronin id.
        roninCount = id + 1; // Increment counter.
        uint256 starterId = nextBladeId; // Starter takes the next forge id.
        nextBladeId = starterId + 1; // Advance global id counter.
        require(bladeSlotById[starterId] == 0, "BLADE_EXISTS"); // No collisions allowed.
        uint256 slot = blades.length; // Append to blade array.
        blades.push(Blade({id: starterId, edge: 1, tempo: 1, roninId: id})); // Starter blade stats.
        bladeSlotById[starterId] = slot + 1; // Store 1-based slot index.
        bladeOwner[starterId] = msg.sender; // Set ownership.
        starterBladeOfRonin[id] = starterId; // Track the starter for attunement protection.
        roninOf[msg.sender] = Ronin({
            id: id,
            hp: RONIN_BASE_HP,
            level: 1,
            equippedBladeId: starterId
        });
        emit RoninAwakened(msg.sender, id, starterId); // Notify creation.
    }

    // === Train a ronin (no bug; still too weak for the boss) ===
    function meditate() external onlyWhitelisted {
        Ronin storage ronin = roninOf[msg.sender];
        require(ronin.hp > 0, "NO_RONIN"); // Must have a living ronin.
        ronin.level += 1; // Increment level.
        ronin.hp += MEDITATION_HP_BONUS; // Gain HP each level.
        emit RoninMeditated(msg.sender, ronin.level, ronin.hp); // Notify progression.
    }

    // === Basic forge (no bug; uses auto-increment id) ===
    function forgeBlade(uint256 edge, uint256 tempo ) external onlyWhitelisted returns (uint256 id) {
        id = _forge(msg.sender, edge, tempo); // Create a new blade for the caller.
    }

    // === Register a herald for re-entrant forging (no bug) ===
    function appointForgeHerald(address herald) external onlyWhitelisted {
        forgeHeraldOf[msg.sender] = herald; // Save herald for the caller.
    }

    // === Forge with herald callback (intentional re-entrancy) ===
    function forgeBladeRite(uint256 edge, uint256 tempo ) external onlyWhitelisted returns (uint256 id) {
        id = _forge(msg.sender, edge, tempo); // Mint the initial blade.
        address herald = forgeHeraldOf[msg.sender]; // Lookup optional herald.
        if (herald != address(0)) {
            heraldCaller = msg.sender; // Cache caller for re-entrant mints.
            heraldDepth = 1; // Arm herald re-entry.
            IForgeHerald(herald).onForgeStamp(msg.sender, id); // External call (re-entrancy hook).
            heraldDepth = 0; // Reset re-entry guard.
            heraldCaller = address(0); // Clear cached caller.
        }
    }

    // === Re-entrant forge target (no bug; gated by heraldDepth) ===
    function forgeBladeViaHerald(uint256 edge, uint256 tempo ) external returns (uint256 id) {
        require(heraldDepth == 1, "HERALD_NOT_ACTIVE"); // Only callable during herald phase.
        require(msg.sender == forgeHeraldOf[heraldCaller], "BAD_HERALD"); // Must be the appointed herald.
        id = _forge(heraldCaller, edge, tempo); // Mint on behalf of the cached caller.
    }

    // === Rite-only entrypoint (no bug; relies on mirrorRite) ===
    function attuneRelic(uint256 bladeId) external onlyRite {
        _attuneRelic(riteCaller, bladeId); // Use cached caller from mirrorRite.
    }

    // === Consume a blade to charge the relic (no bug) ===
    function _attuneRelic(address caller, uint256 bladeId) internal {
        require(caller != address(0), "NO_CALLER"); // Require a cached caller.
        require(whitelist[caller], "NOT_WHITELISTED"); // Caller must be whitelisted.
        Ronin storage ronin = roninOf[caller];
        require(ronin.hp > 0, "NO_RONIN"); // Ronin must be alive.
        require(bladeId == ronin.equippedBladeId, "NOT_EQUIPPED"); // Must equip the blade to consume.

        uint256 starterId = starterBladeOfRonin[ronin.id]; // Fetch the starter id.
        require(bladeId != starterId, "STARTER_PROTECTED"); // Starter blades are protected.

        uint256 slotPlusOne = bladeSlotById[bladeId];
        require(slotPlusOne != 0, "UNKNOWN_BLADE"); // Ensure the blade exists.
        require(bladeOwner[bladeId] == caller, "NOT_OWNER"); // Caller must own it.

        Blade storage blade = blades[slotPlusOne - 1];
        require(blade.roninId == ronin.id, "NOT_BOUND"); // Blade must be bound to this ronin.
        require(blade.tempo > 0, "DULL_BLADE"); // Need a non-zero tempo to gain attunement.

        relics[0].attunement += blade.tempo; // Increase relic attunement by blade tempo.

        blade.edge = 0; // Burn the blade stats after attunement.
        blade.tempo = 0; // Burn the blade stats after attunement.
        blade.roninId = 0; // Clear binding to prevent reuse.
        bladeOwner[bladeId] = address(0); // Clear ownership after consumption.
        ronin.equippedBladeId = starterId; // Re-equip the starter blade.

        emit RelicAttuned(caller, bladeId, relics[0].attunement); // Emit attunement progress.
    }

    // === Bind blade stats using a Merkle proof (bug: XOR path) ===
    function bindBlade(Blade calldata blade, bytes32[] calldata proof ) external onlyWhitelisted {
        uint256 slotPlusOne = bladeSlotById[blade.id];
        require(slotPlusOne != 0, "UNKNOWN_BLADE"); // The blade id must exist.
        require(bladeOwner[blade.id] == msg.sender, "NOT_OWNER"); // Ownership must match.
        require(
            VoidboundMerkle.proveBlade(blade, sanctumRoot(), proof),
            "INVALID_BLADE_PROOF"
        ); // Bug lives in proveBlade: XOR path allows cross-subtree proofs.

        Ronin storage ronin = roninOf[msg.sender];
        require(ronin.hp > 0, "NO_RONIN"); // Ronin must be alive.
        Blade storage stored = blades[slotPlusOne - 1];
        stored.edge = blade.edge; // Overwrite stored edge with proven data.
        stored.tempo = blade.tempo; // Overwrite stored tempo with proven data.
        ronin.equippedBladeId = blade.id; // Auto-equip the updated blade.
        emit BladeBound(msg.sender, blade.id, stored.edge, stored.tempo); // Emit bind event.
    }

    // === Equip helper for mirror rite (no bug) ===
    function _equipForRite(address caller, uint256 bladeId) internal {
        require(caller != address(0), "NO_CALLER"); // Must be invoked with a cached caller.
        require(whitelist[caller], "NOT_WHITELISTED"); // Caller must be whitelisted.
        Ronin storage ronin = roninOf[caller];
        require(ronin.hp > 0, "NO_RONIN"); // Ronin must be alive.
        uint256 slotPlusOne = bladeSlotById[bladeId];
        require(slotPlusOne != 0, "UNKNOWN_BLADE"); // Blade must exist.
        require(bladeOwner[bladeId] == caller, "NOT_OWNER"); // Only owner can equip.
        Blade storage stored = blades[slotPlusOne - 1];
        require(stored.roninId == ronin.id, "NOT_BOUND"); // Must be bound to the ronin.
        ronin.equippedBladeId = bladeId; // Equip for the rite-only flow.
        emit BladeBound(caller, bladeId, stored.edge, stored.tempo); // Emit equip event.
    }

    // === Claim relic stats (bug: XOR path on relic proofs) ===
    function claimRelic( Relic calldata relic, bytes32[] calldata proof ) external onlyWhitelisted onlyClanLeader {
        require(relic.id < relics.length, "UNKNOWN_RELIC"); // Only known relics can be claimed.
        require(
            VoidboundMerkle.proveRelic(relic, sanctumRoot(), proof),
            "INVALID_RELIC_PROOF"
        ); // Bug lives in proveRelic: XOR path allows crafted proofs.

        Ronin storage ronin = roninOf[msg.sender];
        require(ronin.hp > 0, "NO_RONIN"); // Ronin must be alive.

        uint256 slotPlusOne = bladeSlotById[ronin.equippedBladeId];
        require(slotPlusOne != 0, "NO_BLADE"); // Must have an equipped blade.
        Blade storage blade = blades[slotPlusOne - 1];
        require(blade.roninId == ronin.id, "NOT_BOUND"); // Blade must be bound to this ronin.
        uint8 nextLevel = ronin.level + uint8(relic.myth);
        ronin.level = nextLevel; // Apply level upgrade.
        ronin.hp += relic.temper; // Apply HP upgrade.

        uint256 nextEdge = blade.edge + relic.sigil; // Add sigil to blade edge.
        if (nextEdge > MAX_BLADE_EDGE) {
            nextEdge = MAX_BLADE_EDGE; // Clamp edge.
        }
        blade.edge = nextEdge; // Apply edge upgrade.

        uint256 nextTempo = blade.tempo + (relic.isSealed ? 1 : 0); // Sealed adds tempo.
        if (nextTempo > MAX_BLADE_TEMPO) {
            nextTempo = MAX_BLADE_TEMPO; // Clamp tempo.
        }
        blade.tempo = nextTempo; // Apply tempo upgrade.
    }

    // === Boss fight (no bug; weapon stats decide outcome) ===
    function duelShogun() external onlyWhitelisted {
        Ronin storage ronin = roninOf[msg.sender];
        require(ronin.hp > 0, "NO_RONIN"); // Ronin must be alive.
        require(shogun.alive, "SHOGUN_DEAD"); // Boss must be alive.
        uint256 slotPlusOne = bladeSlotById[ronin.equippedBladeId];
        require(slotPlusOne != 0, "NO_BLADE"); // Ronin must have a blade.
        Blade storage blade = blades[slotPlusOne - 1];
        require(blade.roninId == ronin.id, "NOT_BOUND"); // Blade must be bound.

        uint256 damage = blade.edge * blade.tempo + ronin.level; // Single-turn damage formula.
        require(damage > 0, "WEAK_BLADE"); // Prevent trivial zero-damage loops.

        if (damage >= shogun.hp) {
            shogun.hp = 0; // Boss defeated.
            shogun.alive = false; // Mark boss dead.
            emit ShogunDefeated(msg.sender); // Emit victory.
            return;
        }
        shogun.hp -= damage; // Boss survives and loses HP.

        if (ronin.hp <= shogun.strikeDamage) {
            ronin.hp = 0; // Ronin dies on counter-attack.
            return;
        }
        ronin.hp -= shogun.strikeDamage; // Ronin survives but loses HP.
    }

    // === Read-only accessors (no bug) ===
    function getBlade(uint256 id) external view returns (Blade memory) {
        return blades[id]; // Direct blade lookup by slot.
    }

    function getRelic(uint256 id) external view returns (Relic memory) {
        return relics[id]; // Direct relic lookup by slot.
    }

    function getBladeCount() external view returns (uint256) {
        return blades.length; // Total blades in storage.
    }

    function getRelicCount() external view returns (uint256) {
        return relics.length; // Total relics in storage.
    }

    function getShogun() external view returns (VoidShogun memory) {
        return shogun; // Current boss state.
    }

    // === Merkle root for the world (bug sits in VoidboundMerkle path calc) ===
    function sanctumRoot() public view returns (bytes32) {
        return VoidboundMerkle.merkleizeSanctum(
            sanctumName,
            clans.length,
            blades,
            relics
        ); // Build the world root used in proof verification.
    }

    // === Internal helpers (no bug) ===
    function _clanIdOf(address account) internal view returns (uint256) {
        uint256 clanIdPlusOne = clanOf[account]; // Stored as 1-based.
        require(clanIdPlusOne != 0, "NOT_IN_CLAN"); // Ensure membership.
        return clanIdPlusOne - 1; // Convert back to 0-based.
    }

    // === Core forge logic (no bug) ===
    function _forge( address caller, uint256 edge, uint256 tempo ) internal returns (uint256 id) {
        id = nextBladeId; // Allocate the next id.
        Ronin storage ronin = roninOf[caller];
        require(ronin.hp > 0, "NO_RONIN"); // Caller must have a living ronin.
        uint256 clanId = _clanIdOf(caller);
        require(clans[clanId].hasForge, "NO_FORGE"); // Clan must have a forge.
        // NOTE: intentionally allow forging beyond the merkleized range (first 128 blades).
        require(edge <= MAX_BLADE_EDGE && tempo <= MAX_BLADE_TEMPO, "BLADE_STATS_TOO_HIGH"); // Clamp stats.
        require(bladeSlotById[id] == 0, "BLADE_EXISTS"); // Prevent id collisions.
        uint256 slot = blades.length; // Append position.
        blades.push(Blade({id: id, edge: edge, tempo: tempo, roninId: ronin.id})); // Store new blade.
        bladeSlotById[id] = slot + 1; // Save 1-based slot index.
        bladeOwner[id] = caller; // Set ownership.
        nextBladeId = id + 1; // Increment for next forge.
        emit BladeForged(caller, id, slot); // Emit forge event.
    }

    // === Relic creation (no bug) ===
    function _addRelic( bytes32 title, uint256 myth, uint256 temper, uint256 attunement, uint256 sigil, bool isSealed ) internal {
        require(relics.length < VoidboundMerkle.RELICS_NUM_ELEMENTS, "RELIC_CAP"); // Global cap.
        uint256 id = relics.length; // New relic id.
        relics.push(
            Relic({
                id: id,
                title: title,
                myth: myth,
                temper: temper,
                attunement: attunement,
                sigil: sigil,
                isSealed: isSealed
            })
        ); // Store relic with given stats.
    }
}
