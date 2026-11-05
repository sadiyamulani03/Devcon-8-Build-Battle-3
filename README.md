# NightShield — 38 Voices. Zero Revealed Identities.

**Count Every Vote, Name No Voter.**

A complete, security-conscious anonymous ward voting protocol built on **Semaphore V4**. Priya (the ward administrator) enrolls exactly 38 nurse identity commitments into a Semaphore group. Nurses vote anonymously by submitting a Semaphore zero-knowledge proof through a relayer. The smart contract never sees a voter's wallet address and never reads `msg.sender` inside `castVote`.

> **Competition status:** Build Battle 3 submission. Source code is written to be explicit, easy to audit, and to demonstrate every acceptance criterion directly. Cryptographic verification is real Semaphore V4 — there are no mocked ZK verifiers in production code.

---

## 1. Problem statement

In a ward vote, every one of 38 nurses must be able to cast exactly one ballot, but no one — not the administrator, not the relayer, not anyone inspecting the blockchain — must be able to link a vote to the nurse who cast it.

A naive approach (the administrator collects signed votes) reveals who voted how. A naive on-chain approach (each nurse sends a transaction) reveals the voter's wallet address. We need **membership-proof-based anonymous voting**: prove you are one of the 38 enrolled nurses, prove you haven't already voted in this ballot, and reveal only your choice — never your identity.

---

## 2. Solution overview

| Component | Role |
|---|---|
| `WardVoting.sol` | On-chain voting contract. Integrates the real Semaphore V4 verifier. Enforces exactly-38 membership, derives ballot scope, verifies proofs + consumes nullifiers, tallies. |
| `ISemaphore.sol` | Exact Semaphore V4 interface (`@semaphore-protocol/contracts@4.14.5`). |
| Client (`client/src/`) | Identity creation, group reconstruction, local proof generation, tally reading, relayer submission — all using `@semaphore-protocol/core` and `viem`. |
| Relayer | Submits `castVote(ballotId, proof)` without the nurse's wallet or signature. |

**Core idea:** A nurse proves, via a Semaphore zk-SNARK, that (a) her identity commitment is one of the 38 in the ward's Merkle group, and (b) the proof is bound to this ballot's scope. The Semaphore nullifier — derived from her secret scalar and the ballot scope — is consumed on-chain, so she can vote once per ballot. The contract tallies `proof.message` (her selected option). No address, no commitment, no choice is linkable to the submitter.

---

## 3. Architecture diagram

```
+----------------+       +-------------------+       +---------------------+
|   Nurse (client)  |       |     Relayer        |       |   WardVoting.sol       |
|  - Identity      |       |  - submits tx       |       |  - Semaphore group      |
|  - generateProof |------>|  - castVote(proof)  |------>|  - validateProof()      |
|  - (secret local)|       |  - pays gas only    |       |  - nullifier consumed   |
+----------------+       +-------------------+       |  - tally = proof.message  |
                                                    +---------------------+
                                                            ^
                                                            |
                                                    +---------------------+
                                                    |  Real Semaphore V4  |
                                                    |  Semaphore.sol +    |
                                                    |  SemaphoreVerifier  |
                                                    +---------------------+
```

---

## 4. Semaphore V4

Semaphore V4 is a private signaling / anonymous membership protocol. A user proves, in zero knowledge, that:

1. Their identity commitment is a leaf of a group's Merkle tree (membership).
2. They know the secret scalar bound to that commitment.
3. The proof is bound to a `scope` (e.g. a ballot id).
4. The `nullifier = H(scope, secretScalar)` has not already been used in this group+scope.

The on-chain verifier checks the zk-SNARK and records the nullifier, preventing double-signaling. NightShield uses the **real** Semaphore V4 contracts (`Semaphore.sol` + `SemaphoreVerifier`) from `@semaphore-protocol/contracts@4.14.5`, not a mock.

Semaphore proof fields (`ISemaphore.SemaphoreProof`):
- `merkleTreeDepth`, `merkleTreeRoot` — group tree parameters.
- `nullifier` — prevents reuse; consumed atomically by `validateProof`.
- `message` — the voter's chosen option (NightShield tallies this).
- `scope` — domain-separated ballot identifier (NightShield derives this internally).
- `points[8]` — Groth16 proof points.

---

## 5. Identity commitment lifecycle

1. **Create** (`client/src/identity/createIdentity.ts`): The nurse generates a Semaphore `Identity` (EdDSA/Baby Jubjub key pair) **locally**. The commitment `= H(publicKey)` is public.
2. **Enroll** (`WardVoting.enrollMember`): The administrator (Priya) submits the commitment on-chain. Exactly 38 distinct commitments are accepted; duplicates and a 39th are rejected. The administrator authenticates nurse eligibility off-chain before accepting a commitment.
3. **Finalize** (`finalizeWard`): Once exactly 38 are enrolled, the ward is locked. No membership changes afterward.
4. **Backup**: `exportIdentity()` yields a base64 private key. The nurse must back it up; it is never stored on-chain or sent anywhere.

---

## 6. Merkle-tree membership

The 38 commitments form the leaves of an Incremental Merkle Tree (Semaphore's Lean IMT). To vote, the nurse reconstructs the group locally from the public commitments (fetched from `wardCommitments[i]`) and proves her commitment is a leaf via a Merkle proof inside the zk-SNARK. The group root and size are on-chain (`getMerkleTreeRoot`, `getMerkleTreeSize`).

---

## 7. Nullifier and ballot scope

- **Nullifier** `= H(scope, secretScalar)`. It is public on-chain after voting but reveals nothing about the voter without the secret scalar. `validateProof` consumes it, so the same (group, scope) nullifier cannot be used twice → one vote per nurse per ballot.
- **Ballot scope** is **derived inside the contract** from `keccak256(contractAddress, chainId, ballotId) % SCALAR_FIELD`. It is **never accepted from the caller**. This binds a proof to exactly one ballot and one chain, preventing cross-ballot replay.

---

## 8. Proof-bound voting messages

`castVote(ballotId, proof)` takes **only** `ballotId` and `proof`. There is **no separate option argument**. The tally is incremented at `optionTally[proof.message]`. Therefore:
- The voter's choice is established exclusively by the proof.
- A caller cannot submit a proof for option 0 and claim it was option 1.
- A failed proof reverts and changes nothing.

`castVote` never reads `msg.sender` or `tx.origin`, never stores or emits the submitter, and introduces no caller-dependent authorization. Any party (relayer) may submit a valid proof.

---

## 9. On-chain verification

`castVote` calls `semaphore.validateProof(ballot.groupId, proof)` — the **real** Semaphore V4 `validateProof`, which:
1. Reverts if the nullifier was already used (`Semaphore__YouAreUsingTheSameNullifierTwice`).
2. Reverts if the zk-SNARK is invalid (`Semaphore__InvalidProof`).
3. Otherwise records the nullifier and emits `ProofValidated`.

This is **not** `verifyProof()` (view-only); it atomically consumes the nullifier, so a failed or replayed proof can never double-count.

Checks performed before verification: ballot exists, is open, `block.timestamp <= closingTime`, `proof.scope == ballot.scope`, `proof.message < optionCount`.

---

## 10. Relayer architecture

The relayer (`client/src/relayer/submitAnonymousVote.ts`) accepts a `ballotId` and a `SemaphoreProof`, and calls `castVote` using its own funded account (via `viem`). The nurse:

- never sends her identity secret,
- never signs a transaction,
- never needs a wallet,
- never interacts with the contract directly.

The relayer:
- never modifies `proof.message` or `proof.scope`,
- has no administrator privileges,
- cannot forge a valid Semaphore proof (it lacks the voter's secret scalar).

The contract is independent of relayer identity — `castVote` performs no caller check.

**Privacy honesty:** The relayer can observe submission metadata (IP address, timing, network). NightShield provides **cryptographic anonymity** (vote not linkable to identity on-chain), **not** perfect network-level privacy. Do not claim perfect anonymity.

---

## 11. Exactly 38-member enforcement

Semaphore membership alone does not prove the group has exactly 38 members. NightShield therefore:
- Tracks `wardMemberCount`.
- Rejects duplicate commitments (`DuplicateCommitment`).
- Rejects a 39th member (`GroupFull`).
- Prevents membership changes after finalization.
- Requires exactly 38 members before `finalizeWard()`.
- Requires a finalized ward before `createBallot()`.

No nurse names or personal identifiers are stored on-chain — only public commitments.

---

## 12. Test coverage and commands

Foundry tests: `test/WardVoting.t.sol` (28 tests) plus the isolated stub `test/mocks/MockSemaphore.sol`.

Client tests: `client/test/*.ts` (vitest) covering identity creation/import/export and proof generation.

Run:
```
forge build
forge test -vvv
forge fmt --check

# client
npx tsc --noEmit        # typecheck
npx vitest run          # client tests (requires full @semaphore-protocol + vite stack)
```

**Test separation note:** `MockSemaphore` is a clearly-isolated, test-only stub. It is never used by production `WardVoting`. Real Semaphore verification is exercised by `WardVoting.sol` calling `ISemaphore.validateProof()`.

---

## 13. Installation

```
# Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Node.js dependencies (client)
npm install
```

Semaphore V4 contracts are vendored under `lib/semaphore` (`@semaphore-protocol/contracts@4.14.5`).

---

## 14. Local development

```
# 1. Start a local node
anvil

# 2. Deploy
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# 3. Enroll 38 commitments, finalize the ward, create and open a ballot
#    (see Contract interaction examples below)

# 4. Run tests
forge test -vvv
```

---

## 15. Contract interaction examples

```solidity
// Deploy (Priya is the deployer/owner)
WardVoting voting = new WardVoting(semaphore);

// Priya enrolls exactly 38 nurse commitments (off-chain authentication first)
for (uint256 i = 0; i < 38; i++) {
    voting.enrollMember(commitment[i]);
}
voting.finalizeWard();

// Priya creates a ballot
uint256 ballotId = voting.createBallot(
    "Renovate the ward lounge?",
    ["Yes", "No"],
    openingTime,
    closingTime
);
voting.openBallot(ballotId);

// A nurse (via relayer) votes — the contract never sees her address
voting.castVote(ballotId, proof);

// Read the tally (public, no voter info)
(uint256 total, uint256[] counts, uint8 status, uint256 closing, uint256 gid, uint256 scope) =
    voting.getTally(ballotId);
```

---

## 16. Privacy guarantees

**PRIVATE (never on-chain, never revealed):**
- The nurse's identity secret / private key.
- The nurse's identity-to-commitment relationship.
- The individual vote choice (`proof.message` is tallied only in aggregate).
- The voter-to-nullifier association (nullifier reveals nothing without the secret scalar).

**PUBLIC (on-chain / observable):**
- Group commitments (`wardCommitments`) and Merkle root.
- Ballot question, options, opening/closing time.
- `proof.scope`, `proof.nullifier`, `proof.points` (emitted by `validateProof`).
- Aggregate tallies (`getTally`).
- Transaction timing and relayer metadata (observable by the relayer and network).

A tally does **not** reveal individual choices cryptographically, but small groups plus auxiliary information (timing, relayer metadata, known voting patterns) can still create inference risks.

---

## 17. Public information

Everything emitted or stored by `WardVoting` is public: ballot questions/options, closing time, scope, group id, nullifiers, proofs (via Semaphore's `ProofValidated` event), and aggregate tallies. No voter identity, wallet address, or identity commitment is ever stored or emitted.

---

## 18. Threat model

- **Relayer:** honest-but-curious for submission; may observe metadata but cannot forge votes or link votes to identities (lacks secret scalars).
- **Network observer:** may correlate timing/IP with submissions — mitigations (mix networks, Tor) are outside scope.
- **Administrator:** authenticates the initial 38 nurses; cannot alter tallies, bypass proofs, or learn individual votes.
- **Voter:** must safeguard her identity secret; loss = loss of ability to prove membership/vote.

---

## 19. Remaining trust assumptions

1. The ward administrator authenticates the initial 38 nurses before accepting commitments.
2. Voters secure their identity secrets (never share, always back up).
3. The relayer does not collude with network observers to de-anonymize via metadata.
4. The Semaphore trusted setup and verifier implementation are correct.
5. Network metadata may still enable timing correlation.

---

## 20. Limitations

- Cryptographic anonymity ≠ network-level privacy (relayer sees metadata).
- The administrator controls which commitments are enrolled (initial trust anchor).
- Small-group inference: with only 38 voters, published tallies plus side information can narrow down choices.
- A relayer is required for wallet-less submission; without one, a nurse needs her own wallet/gas.
- Lost identity secret = lost voting ability (no recovery by design).

---

## 21. Security considerations

- `castVote` performs no caller-dependent authorization; eligibility is proven exclusively by the Semaphore proof.
- The ballot scope is derived internally and reduced modulo the BN254 scalar field; callers cannot supply it.
- The tally is derived from `proof.message`; there is no manipulable option argument.
- `validateProof` atomically consumes the nullifier — no view-only substitution.
- Administrators cannot modify tallies or bypass proof verification.
- Custom errors and events emit no voter identities.
- `checks-effects-interactions` ordering is used; no unnecessary external calls.

---

## Disclaimer

This is a competition buildathon submission. It demonstrates the acceptance criteria in source form. Production deployment requires additional auditing, key-management, and relayer/network-hardening design.
