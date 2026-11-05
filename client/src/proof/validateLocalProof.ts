import { verifyProof } from "@semaphore-protocol/proof";

/**
 * Validates a Semaphore proof locally on the client.
 *
 * This is a client-side sanity check only. It does not replace on-chain
 * verification by the real Semaphore verifier, which is what consumes the
 * nullifier and authorizes the vote.
 *
 * @returns true if the proof is cryptographically valid.
 */
export async function validateLocalProof(proof: {
  merkleTreeDepth: number;
  merkleTreeRoot: string;
  nullifier: string;
  message: string;
  scope: string;
  points: bigint[] | string[];
}): Promise<boolean> {
  return verifyProof(proof as never);
}
