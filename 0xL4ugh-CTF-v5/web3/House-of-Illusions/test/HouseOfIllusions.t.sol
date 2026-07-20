// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "src/Setup.sol";
import "src/MirrorProxy.sol";
import { IllusionHouse as IllusionHouseV1 } from "src/solution/IllusionHouse.sol";
import { IllusionHouseV1Commented } from "test/mocks/IllusionHouseV1Commented.sol";

contract HouseOfIllusionsTest is Test {
    Setup challenge;
    address visitor = address(0xBEEF);
    bytes32 constant SIGIL = bytes32("0xAnan or Tensai?");
    bytes4 constant ADMIT_SELECTOR =
        bytes4(keccak256("admit(address,bytes)"));
    uint256 constant PATRON_TAG = 1;

    function setUp() public {
        vm.deal(address(this), 200 ether);
        vm.deal(visitor, 1 ether);
        challenge = new Setup{value: 100 ether}(visitor);
    }

    function test_fullFlow_overlapUpgrade() public {
        address house = challenge.house();
        IllusionHouseV1 implementation = new IllusionHouseV1();

        _reframe(address(implementation));

        vm.startPrank(visitor);
        bytes memory data = _overlapCalldata(house, SIGIL, 0x20);
        (bool ok, ) = house.call(data);
        assertTrue(ok, "admit failed");

        (ok, ) = house.call(
            abi.encodeWithSignature("appointCurator(address)", visitor)
        );
        assertTrue(ok, "appoint failed");

        vm.stopPrank();

        assertTrue(challenge.isSolved());
    }

    function test_overlapPayloadRejectedWithoutUpgrade() public {
        address house = challenge.house();
        bytes memory data = _overlapCalldata(house, SIGIL, 0x20);

        vm.prank(visitor);
        (bool ok, ) = house.call(data);
        assertFalse(ok, "overlap should fail on v2");
    }

    function test_canonicalPayloadRejectedEvenWithUpgrade() public {
        address house = challenge.house();
        IllusionHouseV1 implementation = new IllusionHouseV1();

        _reframe(address(implementation));

        bytes memory data = _canonicalCalldata(house, SIGIL);
        vm.prank(visitor);
        (bool ok, ) = house.call(data);
        assertFalse(ok, "canonical should fail without overlap");
    }

    function test_wrongSigilRejectedEvenWithUpgrade() public {
        address house = challenge.house();
        IllusionHouseV1 implementation = new IllusionHouseV1();

        _reframe(address(implementation));

        bytes memory data = _overlapCalldata(
            house,
            bytes32("BAD_SIGIL"),
            0x20
        );

        vm.prank(visitor);
        (bool ok, ) = house.call(data);
        assertFalse(ok, "wrong sigil should fail");
    }

    function test_wrongOffsetRejectedEvenWithUpgrade() public {
        address house = challenge.house();
        IllusionHouseV1 implementation = new IllusionHouseV1();

        _reframe(address(implementation));

        bytes memory data = _overlapCalldata(house, SIGIL, 0x40);
        vm.prank(visitor);
        (bool ok, ) = house.call(data);
        assertFalse(ok, "wrong offset should fail");
    }

    function test_nonCuratorPatronRejected() public {
        address house = challenge.house();
        IllusionHouseV1 implementation = new IllusionHouseV1();

        _reframe(address(implementation));

        bytes memory data = _overlapCalldata(visitor, SIGIL, 0x20);
        vm.prank(visitor);
        (bool ok, ) = house.call(data);
        assertFalse(ok, "non-curator patron should fail");
    }

    function test_appointCuratorRequiresMask() public {
        address house = challenge.house();
        vm.prank(visitor);
        (bool ok, ) = house.call(
            abi.encodeWithSignature("appointCurator(address)", visitor)
        );
        assertFalse(ok, "should fail without mask");
    }

    function test_upgradeAllowsCommentOnlyChanges() public {
        IllusionHouseV1Commented implementation = new IllusionHouseV1Commented();

        _reframe(address(implementation));

        assertTrue(_proxy().reframed());
    }

    function _proxy() internal view returns (MirrorProxy) {
        return MirrorProxy(payable(challenge.house()));
    }

    function _reframe(address implementation) internal {
        vm.prank(visitor);
        _proxy().reframe(implementation);
    }

    function _overlapCalldata(
        address patron,
        bytes32 sigil,
        uint256 offset
    ) internal pure returns (bytes memory) {
        uint256 patronWord = uint256(uint160(patron)) | (PATRON_TAG << 160);
        return
            abi.encodePacked(
                ADMIT_SELECTOR,
                bytes32(patronWord),
                bytes32(offset),
                sigil
            );
    }

    function _canonicalCalldata(address patron, bytes32 sigil)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory sigilBytes = abi.encodePacked(sigil);
        return abi.encodeWithSelector(ADMIT_SELECTOR, patron, sigilBytes);
    }
}
