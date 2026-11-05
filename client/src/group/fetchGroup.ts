import { createPublicClient, http, getContract, parseAbi } from "viem";
import { Group } from "@semaphore-protocol/group";

/**
 * Minimal WardVoting ABI surface needed by the client to reconstruct a Semaphore
 * group and read ballot configuration. The full ABI can be regenerated from the
 * Forge artifacts (out/WardVoting.sol/WardVoting.json).
 */
const WARD_VOTING_ABI = parseAbi([
  "function wardMemberCount() view returns (uint256)",
  "function wardCommitments(uint256) view returns (uint256)",
  "function ballotScope(uint256) view returns (uint256)",
  "function ballotGroupId(uint256) view returns (uint256)",
  "function ballotClosingTime(uint256) view returns (uint256)",
  "function ballotStatus(uint256) view returns (uint8)",
  "function getTally(uint256) view returns (uint256 totalVotes, uint256[] optionCounts, uint8 status, uint256 closingTime, uint256 groupId, uint256 scope)"
]);

/**
 * Fetches the ward's enrolled identity commitments from the chain and reconstructs
 * the Semaphore Merkle group locally.
 *
 * The commitments are public on-chain data. The client uses them to rebuild the
 * Merkle tree so it can generate a membership proof. No identity secrets are
 * involved in this step.
 */
export async function fetchGroup({
  rpcUrl,
  wardVotingAddress,
}: {
  rpcUrl: string;
  wardVotingAddress: `0x${string}`;
}): Promise<{
  group: Group;
  memberCount: number;
  commitments: bigint[];
}> {
  const publicClient = createPublicClient({
    transport: http(rpcUrl),
  });

  const contract = getContract({
    address: wardVotingAddress,
    abi: WARD_VOTING_ABI,
    publicClient,
  });

  const memberCount = (await contract.read.wardMemberCount()) as bigint;
  const commitments: bigint[] = [];
  for (let i = 0n; i < memberCount; i++) {
    commitments.push((await contract.read.wardCommitments([i])) as bigint);
  }

  const group = new Group(commitments.map((c) => c));

  return { group, memberCount: Number(memberCount), commitments };
}
