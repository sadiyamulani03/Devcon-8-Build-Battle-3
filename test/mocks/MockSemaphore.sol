// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ISemaphore } from "../../contracts/interfaces/ISemaphore.sol";

/// @title MockSemaphore
/// @notice TEST-ONLY stub of the Semaphore V4 verifier. Not production code.
contract MockSemaphore is ISemaphore {
    mapping(uint256 => mapping(uint256 => bool)) public nullifiers;
    uint256 public groupCounterValue;
    bool public shouldRevertInvalidProof;

    constructor() {
        groupCounterValue = 0;
        shouldRevertInvalidProof = false;
    }

    function setShouldRevertInvalidProof(bool value) external {
        shouldRevertInvalidProof = value;
    }

    function resetNullifiers() external {
        groupCounterValue = 0;
    }

    function groupCounter() external view override returns (uint256) {
        return groupCounterValue;
    }

    function createGroup() external override returns (uint256) {
        return _createGroup(address(this), 1 hours);
    }

    function createGroup(address admin) external override returns (uint256) {
        return _createGroup(admin, 1 hours);
    }

    function createGroup(address admin, uint256 merkleTreeDuration) external override returns (uint256) {
        return _createGroup(admin, merkleTreeDuration);
    }

    function _createGroup(address admin, uint256 merkleTreeDuration) internal returns (uint256) {
        uint256 gid = groupCounterValue;
        groupCounterValue += 1;
        return gid;
    }

    function updateGroupAdmin(uint256 groupId, address newAdmin) external override { }
    function acceptGroupAdmin(uint256 groupId) external override { }
    function updateGroupMerkleTreeDuration(uint256 groupId, uint256 newMerkleTreeDuration) external override { }

    function addMember(uint256 groupId, uint256 identityCommitment) external override { }
    function addMembers(uint256 groupId, uint256[] calldata identityCommitments) external override { }
    function updateMember(
        uint256 groupId,
        uint256 oldIdentityCommitment,
        uint256 newIdentityCommitment,
        uint256[] calldata merkleProofSiblings
    ) external override { }
    function removeMember(uint256 groupId, uint256 identityCommitment, uint256[] calldata merkleProofSiblings)
        external
        override
    { }

    function validateProof(uint256 groupId, ISemaphore.SemaphoreProof calldata proof) external override {
        if (nullifiers[groupId][proof.nullifier]) {
            revert ISemaphore.Semaphore__YouAreUsingTheSameNullifierTwice();
        }
        if (shouldRevertInvalidProof) {
            revert ISemaphore.Semaphore__InvalidProof();
        }
        nullifiers[groupId][proof.nullifier] = true;
        emit ProofValidated(
            groupId,
            proof.merkleTreeDepth,
            proof.merkleTreeRoot,
            proof.nullifier,
            proof.message,
            proof.scope,
            proof.points
        );
    }

    function verifyProof(uint256 groupId, ISemaphore.SemaphoreProof calldata proof)
        external
        view
        override
        returns (bool)
    {
        return !shouldRevertInvalidProof;
    }
}
