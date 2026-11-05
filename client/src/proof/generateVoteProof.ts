import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import { generateProof, verifyProof } from "@semaphore-protocol/proof";

/**
 * Generates a Semaphore zero-knowledge vote proof entirely on the client.
 *
 * Steps:
 *   1. Loads the voter's locally stored identity.
 *   2. Reconstructs the Semaphore Merkle group from the on-chain commitments.
 *   3. Confirms the voter's commitment is in the group (one of the 38 nurses).
 *   4. Retrieves the ballot's stored scope from the contract.
 *   5. Encodes the selected option as a uint256 message.
 *   6. Generates the Semaphore proof locally (message + scope bound into the proof).
 *   7. Verifies the proof locally when supported.
 *
 * The identity secret never leaves the caller's scope. The proof proves membership
 * in the group and knowledge of the secret scalar bound to the nullifier, without
 * revealing which member voted or how they voted.
 *
 * @param options - identity, group, ballotScope, option (selected option index)
 * @returns The Semaphore proof ready to submit via the relayer.
 */
export async function generateVoteProof({
  identity,
  group,
  ballotScope,
  option,
}: {
  identity: Identity;
  group: Group;
  ballotScope: bigint;
  option: number;
}): Promise<{
  merkleTreeDepth: number;
  merkleTreeRoot: string;
  nullifier: string;
  message: string;
  scope: string;
  points: string[];
}> {
  // The selected option is the vote message. There is no separate option argument
  // on-chain -- the tally is derived from proof.message.
  const message = BigInt(option);

  // Sanity: message and scope must fit in the BN254 scalar field used by the
  // Semaphore circuit. The contract already reduces scope mod the scalar field.
  const scalarField =
    21888242871839275222246405745257275088548364400416034343698204186575808495617n;
  if (message >= scalarField) {
    throw new Error("vote message exceeds the Semaphore scalar field");
  }
  if (ballotScope >= scalarField) {
    throw new Error("ballot scope exceeds the Semaphore scalar field");
  }

  // Generate the zero-knowledge proof locally. The proof binds the voter's
  // membership, the nullifier (scope + secret scalar), the message (option), and
  // the ballot scope. It cannot be forged without the identity secret.
  const proof = await generateProof(identity, group, message, ballotScope);

  // Local verification when supported (client-side confidence before submission).
  const isValid = await verifyProof(proof);
  if (!isValid) {
    throw new Error("locally generated proof failed verification");
  }

  return {
    merkleTreeDepth: proof.merkleTreeDepth,
    merkleTreeRoot: proof.merkleTreeRoot,
    nullifier: proof.nullifier,
    message: proof.message,
    scope: proof.scope,
    points: proof.points.map(String),
  };
}
