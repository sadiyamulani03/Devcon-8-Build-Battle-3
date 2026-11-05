import { Identity } from "@semaphore-protocol/identity";

/**
 * Exports a locally held identity as a base64-encoded private key string.
 *
 * @warning The output is the identity secret. Treat it like a private key: back it
 *          up securely, but never send it to a backend, relayer, administrator, or
 *          smart contract. Anyone with this key can prove membership and vote as
 *          this identity.
 */
export function exportIdentity(identity: Identity): string {
  return identity.export();
}
