// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ISemaphore } from "./interfaces/ISemaphore.sol";

/// @title WardVoting
/// @notice Anonymous ward voting protocol built on Semaphore V4.
/// "Count Every Vote, Name No Voter."
///
/// Priya (the ward administrator) creates a ward, enrolls exactly 38 nurse
/// identity commitments into a Semaphore group, finalizes the group, and then
/// creates ballots. Nurses vote anonymously by submitting a Semaphore zero-knowledge
/// proof through a relayer. The contract never sees the voter's wallet address and
/// never reads msg.sender inside castVote.
///
/// Security:
///   * castVote performs no caller-dependent authorization. Eligibility is
///     established exclusively by the Semaphore proof.
///   * The Semaphore nullifier is consumed atomically inside validateProof(),
///     preventing double voting with the same identity in the same scope.
///   * The ballot scope is derived internally (domain-separated) and is never
///     accepted from the caller as authoritative.
///   * The tally is derived from proof.message; there is no separate option
///     argument that a caller could manipulate.
///   * Administrators cannot modify tallies or bypass proof verification.
contract WardVoting {
    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------
    /// @notice Exactly 38 nurse identity commitments may be enrolled per ward.
    uint256 public constant MAX_MEMBERS = 38;

    /// @notice BN254 scalar field size. Scoped derived for ballots is reduced
    /// modulo this value so it always lies inside the Semaphore circuit's
    /// supported scalar field.
    uint256 public constant SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @notice Ballot statuses.
    uint8 public constant STATUS_CREATED = 0;
    uint8 public constant STATUS_OPEN = 1;
    uint8 public constant STATUS_CLOSED = 2;
    uint8 public constant STATUS_FINALIZED = 3;

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------
    /// @notice Ward administrator (Priya). Set at deployment.
    address public immutable owner;

    /// @notice Real Semaphore V4 verifier contract. Not a mock.
    ISemaphore public immutable semaphore;

    // ---------------------------------------------------------------------
    // Ward state
    // ---------------------------------------------------------------------
    /// @notice Semaphore group id for this ward.
    uint256 public wardGroupId;

    /// @notice Whether ward membership has been finalized (exactly 38 members).
    bool public wardFinalized;

    /// @notice Number of enrolled identity commitments.
    uint256 public wardMemberCount;

    /// @notice Enrolled identity commitments in insertion order (leaf order of the
    /// Semaphore Merkle tree). Public so clients can reconstruct the group locally.
    uint256[] public wardCommitments;

    /// @notice Whether an identity commitment is already enrolled.
    mapping(uint256 => bool) public wardEnrolled;

    // ---------------------------------------------------------------------
    // Ballot state
    // ---------------------------------------------------------------------
    struct Ballot {
        uint256 ballotId;
        string question;
        string[] options;
        uint256 openingTime;
        uint256 closingTime;
        uint256 groupId;
        uint256 scope;
        uint8 status;
        uint256 totalVotes;
        mapping(uint256 => uint256) optionTally; // option index -> vote count
    }

    mapping(uint256 => Ballot) public ballots;
    mapping(uint256 => bool) public ballotIdExists;
    uint256 public ballotCounter;

    // ---------------------------------------------------------------------
    // Events (no voter identity, wallet address, or identity commitment)
    // ---------------------------------------------------------------------
    event WardCreated(address indexed admin, uint256 indexed groupId);
    event MemberEnrolled(uint256 indexed groupId, uint256 commitment, uint256 indexed memberIndex);
    event WardFinalized(uint256 indexed groupId, uint256 memberCount);
    event BallotCreated(
        uint256 indexed ballotId, uint256 groupId, uint256 scope, uint256 openingTime, uint256 closingTime
    );
    event BallotOpened(uint256 indexed ballotId);
    event BallotClosed(uint256 indexed ballotId);
    event BallotFinalized(uint256 indexed ballotId, uint256 totalVotes);
    event VoteCast(uint256 indexed ballotId, uint256 indexed option, uint256 nullifier, uint256 scope);

    // ---------------------------------------------------------------------
    // Custom errors
    // ---------------------------------------------------------------------
    error NotWardAdmin();
    error WardAlreadyFinalized();
    error WardNotFinalized();
    error GroupFull();
    error DuplicateCommitment();
    error InvalidCommitment();
    error BallotDoesNotExist();
    error BallotAlreadyOpen();
    error BallotNotOpen();
    error BallotNotCreated();
    error BallotAlreadyFinalized();
    error BallotAlreadyClosed();
    error InvalidOpeningTime();
    error InvalidClosingTime();
    error InvalidOptions();
    error VotingNotOpened();
    error VotingClosed();
    error InvalidScope();
    error InvalidOption();
    error ZeroAddressSemaphore();

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------
    /// @dev Deploys the ward and creates its Semaphore group. The ward contract
    /// itself is the group admin so it can enroll members.
    constructor(ISemaphore _semaphore) {
        if (address(_semaphore) == address(0)) {
            revert ZeroAddressSemaphore();
        }
        owner = msg.sender;
        semaphore = _semaphore;
        wardGroupId = semaphore.createGroup(address(this));
        emit WardCreated(owner, wardGroupId);
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotWardAdmin();
        }
        _;
    }

    // ---------------------------------------------------------------------
    // Ward membership
    // ---------------------------------------------------------------------
    /// @dev Enrolls a nurse identity commitment into the ward's Semaphore group.
    /// Exactly 38 distinct commitments may be enrolled. The administrator is
    /// responsible for authenticating nurse eligibility off-chain before
    /// accepting a commitment. No names or personal identifiers are stored.
    function enrollMember(uint256 identityCommitment) external onlyOwner {
        if (wardFinalized) {
            revert WardAlreadyFinalized();
        }
        if (identityCommitment == 0) {
            revert InvalidCommitment();
        }
        if (wardEnrolled[identityCommitment]) {
            revert DuplicateCommitment();
        }
        if (wardMemberCount >= MAX_MEMBERS) {
            revert GroupFull();
        }

        wardEnrolled[identityCommitment] = true;
        uint256 memberIndex = wardMemberCount;
        wardMemberCount += 1;
        wardCommitments.push(identityCommitment);

        semaphore.addMember(wardGroupId, identityCommitment);

        emit MemberEnrolled(wardGroupId, identityCommitment, memberIndex);
    }

    /// @dev Finalizes ward membership. Requires exactly 38 enrolled members.
    /// After finalization no membership changes are allowed.
    function finalizeWard() external onlyOwner {
        if (wardFinalized) {
            revert WardAlreadyFinalized();
        }
        if (wardMemberCount != MAX_MEMBERS) {
            revert WardNotFinalized();
        }
        wardFinalized = true;
        emit WardFinalized(wardGroupId, wardMemberCount);
    }

    // ---------------------------------------------------------------------
    // Scope derivation (internal, domain-separated; never caller-supplied)
    // ---------------------------------------------------------------------
    /// @dev Derives the ballot scope from contract address, chain id and ballot
    /// id. The result is reduced modulo the BN254 scalar field so it is always
    /// inside the Semaphore circuit's supported scalar field.
    function _deriveScope(uint256 ballotId) internal view returns (uint256) {
        uint256 scope = uint256(keccak256(abi.encodePacked(address(this), block.chainid, ballotId)));
        return scope % SCALAR_FIELD;
    }

    // ---------------------------------------------------------------------
    // Ballot creation
    // ---------------------------------------------------------------------
    /// @dev Creates a ballot. Requires a finalized ward. The scope is derived
    /// internally and stored; callers cannot supply it.
    function createBallot(string calldata question, string[] calldata options, uint256 openingTime, uint256 closingTime)
        external
        onlyOwner
        returns (uint256 ballotId)
    {
        if (!wardFinalized) {
            revert WardNotFinalized();
        }
        if (options.length == 0) {
            revert InvalidOptions();
        }
        for (uint256 i = 0; i < options.length; i++) {
            if (bytes(options[i]).length == 0) {
                revert InvalidOptions();
            }
        }
        if (openingTime == 0) {
            revert InvalidOpeningTime();
        }
        if (closingTime == 0) {
            revert InvalidClosingTime();
        }
        if (closingTime <= openingTime) {
            revert InvalidClosingTime();
        }
        if (closingTime <= block.timestamp) {
            revert InvalidClosingTime();
        }

        ballotId = ballotCounter;
        if (ballotIdExists[ballotId]) {
            revert BallotAlreadyOpen(); // reuse error for id collision
        }
        ballotIdExists[ballotId] = true;
        ballotCounter += 1;

        uint256 scope = _deriveScope(ballotId);

        string[] memory opts = new string[](options.length);
        for (uint256 i = 0; i < options.length; i++) {
            opts[i] = string(options[i]);
        }

        Ballot storage newBallot = ballots[ballotId];
        newBallot.ballotId = ballotId;
        newBallot.question = string(question);
        newBallot.options = opts;
        newBallot.openingTime = openingTime;
        newBallot.closingTime = closingTime;
        newBallot.groupId = wardGroupId;
        newBallot.scope = scope;
        newBallot.status = STATUS_CREATED;
        newBallot.totalVotes = 0;

        emit BallotCreated(ballotId, wardGroupId, scope, openingTime, closingTime);
    }

    /// @dev Opens a created ballot for voting. Only after the ward is finalized
    /// and the opening time has been reached.
    function openBallot(uint256 ballotId) external onlyOwner {
        Ballot storage b = ballots[ballotId];
        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }
        if (b.status != STATUS_CREATED) {
            revert BallotAlreadyOpen();
        }
        if (block.timestamp < b.openingTime) {
            revert VotingNotOpened();
        }
        b.status = STATUS_OPEN;
        emit BallotOpened(ballotId);
    }

    /// @dev Closes an open ballot early. Votes are already rejected after
    /// closingTime regardless of this call.
    function closeBallot(uint256 ballotId) external onlyOwner {
        Ballot storage b = ballots[ballotId];
        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }
        if (b.status != STATUS_OPEN) {
            revert BallotNotOpen();
        }
        b.status = STATUS_CLOSED;
        emit BallotClosed(ballotId);
    }

    /// @dev Finalizes a ballot after it has closed. Locks the status so the
    /// tally cannot be changed. Does not modify any tally.
    function finalizeBallot(uint256 ballotId) external onlyOwner {
        Ballot storage b = ballots[ballotId];
        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }
        if (b.status == STATUS_FINALIZED) {
            revert BallotAlreadyFinalized();
        }
        if (block.timestamp < b.closingTime && b.status != STATUS_CLOSED) {
            revert VotingClosed();
        }
        b.status = STATUS_FINALIZED;
        emit BallotFinalized(ballotId, b.totalVotes);
    }

    // ---------------------------------------------------------------------
    // Anonymous voting
    // ---------------------------------------------------------------------
    /// @dev Casts an anonymous vote.
    ///
    /// CRITICAL: this function never reads msg.sender or tx.origin, never
    /// stores or emits the transaction submitter, and introduces no
    /// caller-dependent voting authorization. Voter eligibility is established
    /// exclusively by the Semaphore proof, which is verified on-chain by the
    /// real Semaphore validateProof() function. validateProof() atomically
    /// consumes the nullifier, so the same identity cannot vote twice in the
    /// same scope.
    ///
    /// The tally is derived from proof.message. There is no separate option
    /// argument.
    function castVote(uint256 ballotId, ISemaphore.SemaphoreProof calldata proof) external {
        Ballot storage b = ballots[ballotId];

        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }
        if (b.status != STATUS_OPEN) {
            revert BallotNotOpen();
        }
        if (block.timestamp > b.closingTime) {
            revert VotingClosed();
        }
        if (proof.scope != b.scope) {
            revert InvalidScope();
        }
        if (proof.message >= b.options.length) {
            revert InvalidOption();
        }

        // Real Semaphore V4 on-chain verification + nullifier consumption.
        // This call reverts on an invalid proof or a reused nullifier and
        // reverts all state changes if it fails.
        semaphore.validateProof(b.groupId, proof);

        b.optionTally[proof.message] += 1;
        b.totalVotes += 1;

        emit VoteCast(ballotId, proof.message, proof.nullifier, proof.scope);
    }

    // ---------------------------------------------------------------------
    // Tally
    // ---------------------------------------------------------------------
    /// @dev Returns the publicly verifiable tally for a ballot.
    /// sum(optionCounts) == totalVotes by construction.
    function getTally(uint256 ballotId)
        external
        view
        returns (
            uint256 totalVotes,
            uint256[] memory optionCounts,
            uint8 status,
            uint256 closingTime,
            uint256 groupId,
            uint256 scope
        )
    {
        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }

        Ballot storage b = ballots[ballotId];

        optionCounts = new uint256[](b.options.length);
        uint256 sum = 0;
        for (uint256 i = 0; i < b.options.length; i++) {
            optionCounts[i] = b.optionTally[i];
            sum += b.optionTally[i];
        }

        return (b.totalVotes, optionCounts, b.status, b.closingTime, b.groupId, b.scope);
    }

    /// @dev Returns the stored scope for a ballot (used by clients to generate proofs).
    function ballotScope(uint256 ballotId) external view returns (uint256) {
        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }
        return ballots[ballotId].scope;
    }

    /// @dev Returns the Semaphore group id for a ballot.
    function ballotGroupId(uint256 ballotId) external view returns (uint256) {
        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }
        return ballots[ballotId].groupId;
    }

    /// @dev Returns the closing time for a ballot.
    function ballotClosingTime(uint256 ballotId) external view returns (uint256) {
        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }
        return ballots[ballotId].closingTime;
    }

    /// @dev Returns the status for a ballot.
    function ballotStatus(uint256 ballotId) external view returns (uint8) {
        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }
        return ballots[ballotId].status;
    }

    /// @dev Returns the number of options for a ballot.
    function ballotOptionCount(uint256 ballotId) external view returns (uint256) {
        if (!ballotIdExists[ballotId]) {
            revert BallotDoesNotExist();
        }
        return ballots[ballotId].options.length;
    }

    receive() external payable { }
    fallback() external payable { }
}
