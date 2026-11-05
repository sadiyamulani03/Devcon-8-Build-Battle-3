import { Identity } from "@semaphore-protocol/identity";

/**
 * Creates a new Semaphore identity locally.
 *
 * The identity is an EdDSA key pair over Baby Jubjub. Its commitment (the hash of
 * the public key) is what gets enrolled on-chain. The private key / secret scalar
 * MUST stay on the voter's device and must never be transmitted anywhere.
 *
 * @returns The locally created identity and its public commitment string.
 */
export function createIdentity(): {
  identity: Identity;
  commitment: string;
} {
  const identity = new Identity(); // random private key, generated locally
  return {
    identity,
    commitment: identity.commitment.toString(),
  };
}
