// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {VoidBoundBlade} from "src/Setup.sol";

contract Deploy is Script {
    function run() external returns (VoidBoundBlade challenge) {
        address player = vm.envAddress("PLAYER");
        vm.startBroadcast();
        challenge = new VoidBoundBlade(player);
        vm.stopBroadcast();
    }
}
