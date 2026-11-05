import { createPublicClient, http, getContract, parseAbi } from "viem";

/**
 * Publicly verifiable ballot tally. Reads on-chain state only; no voter identity
 * or wallet address is involved.
 */
export const TALLY_ABI = parseAbi([
  "function getTally(uint256 ballotId) view returns (uint256 totalVotes, uint256[] optionCounts, uint8 status, uint256 closingTime, uint256 groupId, uint256 scope)",
  "function ballotStatus(uint256) view returns (uint8)",
  "function ballotClosingTime(uint256) view returns (uint256)",
  "function ballotScope(uint256) view returns (uint256)",
  "function ballotGroupId(uint256) view returns (uint256)",
  "function ballotOptionCount(uint256) view returns (uint256)"
]);

export type BallotStatus = "created" | "open" | "closed" | "finalized";

export function statusToString(status: number): BallotStatus {
  return [ "created", "open", "closed", "finalized" ][status] ?? "created";
}

export async function getTally({
  rpcUrl,
  wardVotingAddress,
  ballotId,
}: {
  rpcUrl: string;
  wardVotingAddress: `0x${string}`;
  ballotId: bigint | number;
}): Promise<{
  totalVotes: bigint;
  optionCounts: bigint[];
  status: BallotStatus;
  statusCode: number;
  closingTime: bigint;
  groupId: bigint;
  scope: bigint;
}> {
  const publicClient = createPublicClient({ transport: http(rpcUrl) });

  const contract = getContract({
    address: wardVotingAddress,
    abi: TALLY_ABI,
    publicClient,
  });

  const [totalVotes, optionCounts, status, closingTime, groupId, scope] =
    (await contract.read.getTally([BigInt(ballotId)])) as [
      bigint,
      bigint[],
      number,
      bigint,
      bigint,
      bigint,
    ];

  return {
    totalVotes,
    optionCounts,
    status: statusToString(status),
    statusCode: status,
    closingTime,
    groupId,
    scope,
  };
}
