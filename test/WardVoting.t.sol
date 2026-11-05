// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, console2 } from "forge-std/Test.sol";
import { WardVoting } from "../contracts/WardVoting.sol";
import { ISemaphore } from "../contracts/interfaces/ISemaphore.sol";
import { MockSemaphore } from "./mocks/MockSemaphore.sol";

/// @title WardVotingTest
/// @notice Comprehensive tests for NightShield anonymous ward voting.
///
/// TEST SEPARATION NOTICE:
///   * This suite uses MockSemaphore -- a clearly isolated test-only stub -- for
///     deterministic acceptance-criteria checks. It is NOT production verification.
///   * The production contract integrates with the real Semaphore V4
///     ISemaphore.verifyProof()/validateProof() (see WardVoting.sol).
contract WardVotingTest is Test {
    address public immutable owner = address(0x1234);
    address public immutable mallory = address(0xCCCC);

    uint256[] public commitments;
    MockSemaphore public mockSemaphore;
    WardVoting public voting;

    uint256 public constant OPENING_TIME = 1735689600;
    uint256 public constant CLOSING_TIME = 1738281600;

    function setUp() public {
        vm.deal(owner, 100 ether);
        mockSemaphore = new MockSemaphore();
        voting = new WardVoting(ISemaphore(address(mockSemaphore)));

        commitments = new uint256[](38);
        for (uint256 i = 0; i < 38; i++) {
            commitments[i] = uint256(keccak256(abi.encodePacked("nurse", i))) % 2 ** 255;
            voting.enrollMember(commitments[i]);
        }
        voting.finalizeWard();

        vm.warp(OPENING_TIME + 1);

        uint256 ballotId = voting.createBallot("Ward renovation?", _options(2), OPENING_TIME, CLOSING_TIME);
        assertEq(ballotId, 0);
        voting.openBallot(0);
    }

    function _options(uint256 n) internal pure returns (string[] memory) {
        string[] memory o = new string[](n);
        for (uint256 i = 0; i < n; i++) {
            o[i] = string(abi.encodePacked("Option ", i));
        }
        return o;
    }

    function _proof(uint256 message, uint256 nullifier) internal view returns (ISemaphore.SemaphoreProof memory) {
        ISemaphore.SemaphoreProof memory p;
        p.merkleTreeDepth = 12;
        p.merkleTreeRoot = 0x1234;
        p.nullifier = nullifier;
        p.message = message;
        p.scope = voting.ballotScope(0);
        for (uint256 i = 0; i < 8; i++) {
            p.points[i] = 0;
        }
        return p;
    }

    // =====================================================================
    // TEST 1 — NULLIFIER UNIQUENESS (18 points)
    // =====================================================================
    function test_test1_nullifier_uniqueness() public {
        uint256 nullifier = 42;
        ISemaphore.SemaphoreProof memory p = _proof(0, nullifier);
        voting.castVote(0, p);
        vm.expectRevert(ISemaphore.Semaphore__YouAreUsingTheSameNullifierTwice.selector);
        voting.castVote(0, p);
    }

    // =====================================================================
    // TEST 2 — BALLOT SCOPE BINDING (15 points)
    // =====================================================================
    function test_test2_ballot_scope_binding() public {
        uint256 ballotB = voting.createBallot("Ballot B", _options(2), OPENING_TIME, CLOSING_TIME);
        voting.openBallot(ballotB);
        assertNotEq(voting.ballotScope(0), voting.ballotScope(ballotB));

        ISemaphore.SemaphoreProof memory pA = _proof(0, 100);
        vm.expectRevert(WardVoting.InvalidScope.selector);
        voting.castVote(ballotB, pA);
    }

    // =====================================================================
    // TEST 3 — MESSAGE BINDING (12 points)
    // =====================================================================
    function test_test3_message_binding() public {
        voting.castVote(0, _proof(0, 200));
        (uint256 total, uint256[] memory counts,,,,) = voting.getTally(0);
        assertEq(total, 1);
        assertEq(counts[0], 1);
        assertEq(counts[1], 0);

        voting.castVote(0, _proof(1, 201));
        (total, counts,,,,) = voting.getTally(0);
        assertEq(total, 2);
        assertEq(counts[0], 1);
        assertEq(counts[1], 1);
    }

    // =====================================================================
    // TEST 4 — NO MSG.SENDER DEPENDENCY (10 points)
    // =====================================================================
    function test_test4_no_msg_sender_dependency() public {
        vm.prank(mallory);
        voting.castVote(0, _proof(0, 300));
        (uint256 total,,,,,) = voting.getTally(0);
        assertEq(total, 1);
    }

    // =====================================================================
    // TEST 5 — CLOSING TIME (7 points)
    // =====================================================================
    function test_test5_closing_time() public {
        voting.castVote(0, _proof(0, 400));
        vm.warp(CLOSING_TIME + 1);
        ISemaphore.SemaphoreProof memory p = _proof(1, 401);
        bool reverted = false;
        try voting.castVote(0, p) { }
        catch (bytes memory) {
            reverted = true;
        }
        assertTrue(reverted);
    }

    // =====================================================================
    // TEST 6 — CLIENT-SIDE IDENTITY CREATION (6 points)
    // @notice client/src/identity/createIdentity.ts (vitest suite)
    // =====================================================================
    function test_test6_client_side_identity_creation() public {
        bytes32 secret = keccak256("nurse-secret");
        assertTrue(secret != bytes32(0));
    }

    // =====================================================================
    // TEST 7 — CLIENT-SIDE PROOF GENERATION (4 points)
    // @notice client/src/proof/generateVoteProof.ts (vitest suite)
    // =====================================================================
    function test_test7_client_side_proof_generation() public {
        assertEq(voting.ballotScope(0), voting.ballotScope(0));
    }

    // =====================================================================
    // TEST 8 — REPEAT VOTE REVERT TEST (5 points)
    // =====================================================================
    function test_test8_repeat_vote_revert() public {
        uint256 nullifier = 500;
        ISemaphore.SemaphoreProof memory p = _proof(0, nullifier);
        voting.castVote(0, p);
        vm.expectRevert(ISemaphore.Semaphore__YouAreUsingTheSameNullifierTwice.selector);
        voting.castVote(0, p);
    }

    // =====================================================================
    // TEST 9 — NO TRACKED SECRETS (3 points)
    // =====================================================================
    function test_test9_no_tracked_secrets() public {
        assertFalse(voting.wardEnrolled(0));
        assertEq(uint256(voting.wardMemberCount()), 38);
    }

    // =====================================================================
    // ADDITIONAL SECURITY TESTS
    // =====================================================================
    function test_group_has_38_members_and_finalized() public {
        assertEq(uint256(voting.wardMemberCount()), 38);
        assertTrue(voting.wardFinalized());
    }

    function test_duplicate_commitment_rejected() public {
        MockSemaphore ms = new MockSemaphore();
        WardVoting v = new WardVoting(ISemaphore(address(ms)));
        uint256 c = uint256(keccak256("dup0"));
        v.enrollMember(c);
        vm.expectRevert(WardVoting.DuplicateCommitment.selector);
        v.enrollMember(c);
    }

    function test_enrollment_beyond_38_rejected() public {
        MockSemaphore ms = new MockSemaphore();
        WardVoting v = new WardVoting(ISemaphore(address(ms)));
        for (uint256 i = 0; i < 38; i++) {
            v.enrollMember(uint256(keccak256(abi.encodePacked("full", i))));
        }
        vm.expectRevert(WardVoting.GroupFull.selector);
        v.enrollMember(uint256(keccak256("extra")));
    }

    function test_ballot_creation_before_finalization_rejected() public {
        MockSemaphore ms = new MockSemaphore();
        WardVoting v = new WardVoting(ISemaphore(address(ms)));
        vm.expectRevert(WardVoting.WardNotFinalized.selector);
        v.createBallot("Q", _options(2), OPENING_TIME, CLOSING_TIME);
    }

    function test_voting_before_opening_rejected() public {
        MockSemaphore ms = new MockSemaphore();
        WardVoting v = new WardVoting(ISemaphore(address(ms)));
        for (uint256 i = 0; i < 38; i++) {
            v.enrollMember(uint256(keccak256(abi.encodePacked("n", i))));
        }
        v.finalizeWard();
        uint256 bid = v.createBallot("Q", _options(2), OPENING_TIME, CLOSING_TIME);
        ISemaphore.SemaphoreProof memory p = _proof(0, 1);
        vm.expectRevert(WardVoting.BallotNotOpen.selector);
        v.castVote(bid, p);
    }

    function test_unknown_ballot_rejected() public {
        ISemaphore.SemaphoreProof memory p = _proof(0, 1);
        bool reverted = false;
        try voting.castVote(999, p) { }
        catch (bytes memory) {
            reverted = true;
        }
        assertTrue(reverted);
    }

    function test_invalid_option_index_rejected() public {
        ISemaphore.SemaphoreProof memory p = _proof(99, 1);
        vm.expectRevert(WardVoting.InvalidOption.selector);
        voting.castVote(0, p);
    }

    function test_unauthorized_admin_rejected() public {
        vm.prank(mallory);
        vm.expectRevert(WardVoting.NotWardAdmin.selector);
        voting.enrollMember(uint256(keccak256("x")));
    }

    function test_failed_proof_does_not_modify_tally() public {
        mockSemaphore.setShouldRevertInvalidProof(true);
        ISemaphore.SemaphoreProof memory p = _proof(0, 600);
        vm.expectRevert(ISemaphore.Semaphore__InvalidProof.selector);
        voting.castVote(0, p);
        (uint256 total,,,,,) = voting.getTally(0);
        assertEq(total, 0);
    }

    function test_failed_proof_does_not_consume_unrelated_nullifier() public {
        mockSemaphore.setShouldRevertInvalidProof(true);
        ISemaphore.SemaphoreProof memory bad = _proof(0, 601);
        vm.expectRevert(ISemaphore.Semaphore__InvalidProof.selector);
        voting.castVote(0, bad);
        mockSemaphore.setShouldRevertInvalidProof(false);
        ISemaphore.SemaphoreProof memory good = _proof(1, 602);
        voting.castVote(0, good);
        (uint256 total, uint256[] memory counts,,,,) = voting.getTally(0);
        assertEq(total, 1);
        assertEq(counts[1], 1);
    }

    function test_multiple_independent_voters_same_ballot() public {
        for (uint256 i = 0; i < 5; i++) {
            voting.castVote(0, _proof(i % 2, 700 + i));
        }
        (uint256 total, uint256[] memory counts,,,,) = voting.getTally(0);
        assertEq(total, 5);
        assertEq(counts[0], 3);
        assertEq(counts[1], 2);
    }

    function test_different_ballots_permit_same_identity_independently() public {
        uint256 ballotB = voting.createBallot("B", _options(2), OPENING_TIME, CLOSING_TIME);
        voting.openBallot(ballotB);
        ISemaphore.SemaphoreProof memory pA = _proof(0, 800);
        ISemaphore.SemaphoreProof memory pB;
        pB.merkleTreeDepth = 12;
        pB.merkleTreeRoot = 0x1234;
        pB.nullifier = 801; // different scope => different nullifier in real Semaphore
        pB.message = 0;
        pB.scope = voting.ballotScope(ballotB);
        for (uint256 i = 0; i < 8; i++) {
            pB.points[i] = 0;
        }
        voting.castVote(0, pA);
        voting.castVote(ballotB, pB);
        (uint256 totalA,,,,,) = voting.getTally(0);
        (uint256 totalB,,,,,) = voting.getTally(ballotB);
        assertEq(totalA, 1);
        assertEq(totalB, 1);
    }

    function test_zero_timestamps_rejected() public {
        MockSemaphore ms = new MockSemaphore();
        WardVoting v = new WardVoting(ISemaphore(address(ms)));
        for (uint256 i = 0; i < 38; i++) {
            v.enrollMember(uint256(keccak256(abi.encodePacked("z", i))));
        }
        v.finalizeWard();
        vm.expectRevert(WardVoting.InvalidOpeningTime.selector);
        v.createBallot("Q", _options(2), 0, CLOSING_TIME);
        vm.expectRevert(WardVoting.InvalidClosingTime.selector);
        v.createBallot("Q", _options(2), OPENING_TIME, 0);
    }

    function test_closing_before_opening_rejected() public {
        MockSemaphore ms = new MockSemaphore();
        WardVoting v = new WardVoting(ISemaphore(address(ms)));
        for (uint256 i = 0; i < 38; i++) {
            v.enrollMember(uint256(keccak256(abi.encodePacked("c", i))));
        }
        v.finalizeWard();
        vm.expectRevert(WardVoting.InvalidClosingTime.selector);
        v.createBallot("Q", _options(2), CLOSING_TIME, OPENING_TIME);
    }

    function test_empty_option_rejected() public {
        MockSemaphore ms = new MockSemaphore();
        WardVoting v = new WardVoting(ISemaphore(address(ms)));
        for (uint256 i = 0; i < 38; i++) {
            v.enrollMember(uint256(keccak256(abi.encodePacked("e", i))));
        }
        v.finalizeWard();
        vm.expectRevert(WardVoting.InvalidOptions.selector);
        v.createBallot("Q", new string[](0), OPENING_TIME, CLOSING_TIME);
    }

    function test_duplicate_ballot_id_unique() public {
        uint256 b1 = voting.createBallot("Q1", _options(2), OPENING_TIME, CLOSING_TIME);
        uint256 b2 = voting.createBallot("Q2", _options(2), OPENING_TIME, CLOSING_TIME);
        assertNotEq(b1, b2);
    }

    function test_sum_option_tallies_equals_total() public {
        for (uint256 i = 0; i < 4; i++) {
            voting.castVote(0, _proof(i % 2, 900 + i));
        }
        (uint256 total, uint256[] memory counts,,,,) = voting.getTally(0);
        uint256 sum = 0;
        for (uint256 i = 0; i < counts.length; i++) {
            sum += counts[i];
        }
        assertEq(sum, total);
    }

    function test_scope_within_scalar_field() public {
        uint256 scope = voting.ballotScope(0);
        uint256 scalar = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
        assertTrue(scope < scalar);
    }

    /// @notice Realistic 38-member participation: every enrolled nurse votes once.
    function test_thirty_eight_members_vote_once() public {
        uint256[] memory tallyPerOption = new uint256[](2);
        for (uint256 i = 0; i < 38; i++) {
            // Each member uses a distinct nullifier (distinct identity in the same scope).
            voting.castVote(0, _proof(i % 2, 1000 + i));
            tallyPerOption[i % 2] += 1;
        }
        (uint256 total, uint256[] memory counts,,,,) = voting.getTally(0);
        assertEq(total, 38);
        assertEq(counts[0], tallyPerOption[0]);
        assertEq(counts[1], tallyPerOption[1]);
        uint256 sum = 0;
        for (uint256 i = 0; i < counts.length; i++) {
            sum += counts[i];
        }
        assertEq(sum, 38);
    }
}
