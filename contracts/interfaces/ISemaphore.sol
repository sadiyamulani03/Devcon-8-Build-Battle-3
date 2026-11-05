//SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

/// @title Semaphore contract interface.
/// @notice Exact Semaphore V4 interface. Taken from @semaphore-protocol/contracts v4.
interface ISemaphore {
    error Semaphore__GroupHasNoMembers();
    error Semaphore__MerkleTreeDepthIsNotSupported();
    error Semaphore__MerkleTreeRootIsExpired();
    error Semaphore__MerkleTreeRootIsNotPartOfTheGroup();
    error Semaphore__YouAreUsingTheSameNullifierTwice();
    error Semaphore__InvalidProof();

    /// It defines all the group parameters used by Semaphore.sol.
    struct Group {
        uint256 merkleTreeDuration;
        mapping(uint256 => uint256) merkleRootSupersededDates;
        mapping(uint256 => bool) nullifiers;
    }

    /// It defines all the Semaphore proof parameters used by Semaphore.sol.
    struct SemaphoreProof {
        uint256 merkleTreeDepth;
        uint256 merkleTreeRoot;
        uint256 nullifier;
        uint256 message;
        uint256 scope;
        uint256[8] points;
    }

    /// @dev Event emitted when the Merkle tree duration of a group is updated.
    event GroupMerkleTreeDurationUpdated(
        uint256 indexed groupId, uint256 oldMerkleTreeDuration, uint256 newMerkleTreeDuration
    );

    /// @dev Event emitted when a Semaphore proof is validated.
    event ProofValidated(
        uint256 indexed groupId,
        uint256 merkleTreeDepth,
        uint256 indexed merkleTreeRoot,
        uint256 nullifier,
        uint256 message,
        uint256 indexed scope,
        uint256[8] points
    );

    /// @dev Returns the current value of the group counter.
    function groupCounter() external view returns (uint256);

    /// @dev See {SemaphoreGroups-_createGroup}.
    function createGroup() external returns (uint256);

    /// @dev See {SemaphoreGroups-_createGroup}.
    function createGroup(address admin) external returns (uint256);

    /// @dev It creates a group with a custom Merkle tree duration.
    function createGroup(address admin, uint256 merkleTreeDuration) external returns (uint256);

    /// @dev See {SemaphoreGroups-_updateGroupAdmin}.
    function updateGroupAdmin(uint256 groupId, address newAdmin) external;

    /// @dev See {SemaphoreGroups-_acceptGroupAdmin}.
    function acceptGroupAdmin(uint256 groupId) external;

    /// @dev Updates the group Merkle tree duration.
    function updateGroupMerkleTreeDuration(uint256 groupId, uint256 newMerkleTreeDuration) external;

    /// @dev See {SemaphoreGroups-_addMember}.
    function addMember(uint256 groupId, uint256 identityCommitment) external;

    /// @dev See {SemaphoreGroups-_addMembers}.
    function addMembers(uint256 groupId, uint256[] calldata identityCommitments) external;

    /// @dev See {SemaphoreGroups-_updateMember}.
    function updateMember(
        uint256 groupId,
        uint256 oldIdentityCommitment,
        uint256 newIdentityCommitment,
        uint256[] calldata merkleProofSiblings
    ) external;

    /// @dev See {SemaphoreGroups-_removeMember}.
    function removeMember(uint256 groupId, uint256 identityCommitment, uint256[] calldata merkleProofSiblings) external;

    /// @dev Saves the nullifier hash to prevent double signaling and emits an event
    /// if the zero-knowledge proof is valid.
    function validateProof(uint256 groupId, SemaphoreProof calldata proof) external;

    /// @dev Verifies a zero-knowledge proof by returning true or false.
    function verifyProof(uint256 groupId, SemaphoreProof calldata proof) external view returns (bool);
}
