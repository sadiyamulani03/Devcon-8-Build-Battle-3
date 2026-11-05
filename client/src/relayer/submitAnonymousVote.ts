import {
  createWalletClient,
  http,
  getContract,
  parseAbi,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

/**
 * Submits an anonymous vote on behalf of a nurse through a relayer.
 *
 * The relayer needs only the ballot ID and the Semaphore proof. It never sees the
 * nurse's identity secret, never asks the nurse to sign a transaction, and never
 * needs the nurse's wallet. The WardVoting contract does not check msg.sender, so
 * any funded relayer account may submit a valid proof.
 *
 * @warning A relayer can observe submission metadata (IP, timing, network). This
 *          provides cryptographic anonymity, not perfect network-level privacy.
 */
export async function submitAnonymousVote({
  rpcUrl,
  relayerPrivateKey,
  wardVotingAddress,
  ballotId,
  proof,
}: {
  rpcUrl: string;
  relayerPrivateKey: `0x${string}`;
  wardVotingAddress: `0x${string}`;
  ballotId: bigint | number;
  proof: {
    merkleTreeDepth: number;
    merkleTreeRoot: string;
    nullifier: string;
    message: string;
    scope: string;
    points: bigint[] | string[];
  };
}): Promise<`0x${string}`> {
  const account = privateKeyToAccount(relayerPrivateKey);

  const client = createWalletClient({
    account,
    transport: http(rpcUrl),
  });

  const contract = getContract({
    address: wardVotingAddress,
    abi: parseAbi([
      "function castVote(uint256 ballotId, tuple(uint256 merkleTreeDepth,uint256 merkleTreeRoot,uint256 nullifier,uint256 message,uint256 scope,uint256[8] points) calldata proof) external"
    ]),
    client,
  });

  const tx = await contract.write.castVote([BigInt(ballotId), {
    merkleTreeDepth: proof.merkleTreeDepth,
    merkleTreeRoot: proof.merkleTreeRoot as `0x${string}`,
    nullifier: proof.nullifier as `0x${string}`,
    message: proof.message as `0x${string}`,
    scope: proof.scope as `0x${string}`,
    points: proof.points.map((p) => BigInt(p)),
  }]);

  return tx;
}
