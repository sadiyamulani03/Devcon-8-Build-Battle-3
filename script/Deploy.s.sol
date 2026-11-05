// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script, console2 } from "forge-std/Script.sol";
import { WardVoting } from "../contracts/WardVoting.sol";
import { ISemaphore } from "../contracts/interfaces/ISemaphore.sol";
import { Semaphore } from "@semaphore/Semaphore.sol";
import { SemaphoreVerifier } from "@semaphore/base/SemaphoreVerifier.sol";
import { ISemaphoreVerifier } from "@semaphore/interfaces/ISemaphoreVerifier.sol";

/// @title Deploy
/// @notice Deploys the NightShield voting stack:
///   1. SemaphoreVerifier (real Semaphore V4 verifier)
///   2. Semaphore (real Semaphore V4 contract, wired to the verifier)
///   3. WardVoting (the anonymous ward voting contract, wired to Semaphore)
///
/// The WardVoting contract creates its own Semaphore group internally and acts as
/// the group admin so it can enroll the 38 nurse identity commitments.
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = uint256(keccak256(abi.encodePacked("nightshield-deployer")));

        vm.startBroadcast(deployerPrivateKey);

        // 1. Real Semaphore V4 verifier (not a mock).
        SemaphoreVerifier verifier = new SemaphoreVerifier();

        // 2. Real Semaphore V4 contract.
        Semaphore semaphore = new Semaphore(ISemaphoreVerifier(address(verifier)));

        // 3. WardVoting, wired to the real Semaphore verifier contract.
        WardVoting wardVoting = new WardVoting(ISemaphore(address(semaphore)));

        vm.stopBroadcast();

        console2.log("SemaphoreVerifier:", address(verifier));
        console2.log("Semaphore:", address(semaphore));
        console2.log("WardVoting:", address(wardVoting));
        console2.log("Ward groupId:", wardVoting.wardGroupId());
    }
}
