import { describe, it, expect } from "vitest";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import { generateVoteProof } from "../src/proof/generateVoteProof";
import { confirmMembership } from "../src/group/reconstructGroup";

describe("client-side proof generation (Semaphore V4)", () => {
  it("generates a proof bound to the selected option and ballot scope", async () => {
    // Two nurse identities enrolled in the ward group.
    const idA = new Identity();
    const idB = new Identity();
    const group = new Group([idA.commitment, idB.commitment]);

    // Voter A confirms their commitment is in the group.
    const membership = confirmMembership(group, idA.commitment);
    expect(membership).not.toBeNull();
    expect(membership!.index).toBe(0);

    // Ballot scope as stored by the contract (reduced mod the scalar field).
    const ballotScope = 12345n;

    // Voter A selects option 1.
    const proof = await generateVoteProof({
      identity: idA,
      group,
      ballotScope,
      option: 1,
    });

    // The proof is bound to the selected option (message) and the ballot scope.
    expect(BigInt(proof.message)).toBe(1n);
    expect(BigInt(proof.scope)).toBe(ballotScope);
    expect(proof.points.length).toBe(8);
  });

  it("rejects an option that is not a valid ballot message", async () => {
    const idA = new Identity();
    const group = new Group([idA.commitment]);

    // generateVoteProof throws if the message exceeds the scalar field.
    const scalarField =
      21888242871839275222246405745257275088548364400416034343698204186575808495617n;
    await expect(
      generateVoteProof({
        identity: idA,
        group,
        ballotScope: 1n,
        option: Number(scalarField), // invalid as a sane option index
      })
    ).rejects.toThrow();
  });
});
