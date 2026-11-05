import { Group } from "@semaphore-protocol/group";

/**
 * Reconstructs a Semaphore Merkle group from a list of identity commitments.
 *
 * This is a purely local operation: the group commitments are public data and
 * rebuilding the tree locally requires no secrets.
 */
export function reconstructGroup(commitments: bigint[]): Group {
  return new Group(commitments);
}

/**
 * Confirms that an identity commitment is a member of the group and returns its
 * leaf index and Merkle proof. Used by the voter to prove they are one of the 38
 * enrolled nurses without revealing which one.
 *
 * @returns The member index and the Merkle proof siblings, or null if the
 *          commitment is not in the group.
 */
export function confirmMembership(
  group: Group,
  commitment: bigint
): { index: number; merkleProof: { siblings: bigint[] } } | null {
  const index = group.indexOf(commitment);
  if (index === -1) {
    return null;
  }
  const proof = group.generateMerkleProof(index);
  return {
    index,
    merkleProof: { siblings: proof.siblings.map((s) => s) },
  };
}
