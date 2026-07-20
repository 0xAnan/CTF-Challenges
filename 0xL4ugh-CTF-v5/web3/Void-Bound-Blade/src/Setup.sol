// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/VoidboundSanctum.sol";

contract VoidBoundBlade {
    address public immutable SEEKER;
    VoidboundSanctum public immutable SANCTUM;

    constructor(address player) {
        SEEKER = player;
        SANCTUM = new VoidboundSanctum();
    }

    function isSolved() external view returns (bool) {
        return !SANCTUM.getShogun().alive;
    }
}
