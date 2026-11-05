import { Identity } from "@semaphore-protocol/identity";

/**
 * Imports an identity from a base64-encoded private key previously exported with
 * {@link exportIdentity}.
 *
 * @warning Only import private keys you generated and backed up yourself. Never
 *          import a key received from another party or a backend.
 */
export function importIdentity(privateKeyBase64: string): Identity {
  return Identity.import(privateKeyBase64);
}
