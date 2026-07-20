// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IVoidboundSanctum {
    struct Ronin {
        uint256 id;
        uint256 hp;
        uint8 level;
        uint256 equippedBladeId;
    }

    struct Blade {
        uint256 id;
        uint256 edge;
        uint256 tempo;
        uint256 roninId;
    }

    struct Relic {
        uint256 id;
        bytes32 title;
        uint256 myth;
        uint256 temper;
        uint256 attunement;
        uint256 sigil;
        bool isSealed;
    }

    struct VoidShogun {
        uint256 level;
        uint256 hp;
        bool alive;
        uint256 strikeDamage;
    }

    struct Clan {
        address leader;
        bool hasForge;
        uint256 members;
    }
}
