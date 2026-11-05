import { parseAbi } from "viem";

/**
 * Client-side validation of a vote before it is turned into a Semaphore proof.
 *
 * The on-chain castVote(ballotId, proof) has NO separate option argument: the
 * tally is derived from proof.message. This helper merely confirms the caller's
 * selected option is a valid index for the ballot and returns the message that
 * must be encoded into the proof.
 *
 * No identity secrets or caller addresses are involved.
 */
export function validateVoteOption({
  option,
  optionCount,
}: {
  option: number;
  optionCount: number;
}): { message: bigint; valid: boolean } {
  if (option < 0 || option >= optionCount) {
    return { message: 0n, valid: false };
  }
  return { message: BigInt(option), valid: true };
}

export const CAST_VOTE_ABI = parseAbi([
  "function castVote(uint256 ballotId, tuple(uint256 merkleTreeDepth,uint256 merkleTreeRoot,uint256 nullifier,uint256 message,uint256 scope,uint256[8] points) calldata proof) external"
]);
