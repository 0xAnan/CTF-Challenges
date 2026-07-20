// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {IllusionHouse} from "../src/solution/IllusionHouse.sol";

contract ComputeCodeHash is Script {
    function run() external {
        vm.startBroadcast();

        IllusionHouse impl = new IllusionHouse();
        address deployed = address(impl);

        bytes32 codeHash = _codeHash(deployed);

        console2.log("Deployed IllusionHouse at:", deployed);
        console2.log("ALLOWED_CODEHASH (bytes32):");
        console2.logBytes32(codeHash);

        // Also print as uint256 (sometimes useful for copy/paste)
        console2.log("ALLOWED_CODEHASH (uint256):");
        console2.log(uint256(codeHash));

        vm.stopBroadcast();
    }

    function _codeHash(address target) internal view returns (bytes32 hash) {
        assembly {
            let size := extcodesize(target)
            switch lt(size, 2)
            case 1 { hash := 0 }
            default {
                let ptr := mload(0x40)
                extcodecopy(target, ptr, 0, size)
                // Last two bytes are CBOR length; strip metadata before hashing.
                let metaLen := shr(240, mload(add(ptr, sub(size, 2))))
                switch gt(add(metaLen, 2), size)
                case 1 { hash := 0 }
                default {
                    hash := keccak256(ptr, sub(size, add(metaLen, 2)))
                }
            }
        }
    }
}
