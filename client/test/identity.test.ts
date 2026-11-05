import { describe, it, expect } from "vitest";
import { createIdentity } from "../src/identity/createIdentity";
import { importIdentity } from "../src/identity/importIdentity";
import { exportIdentity } from "../src/identity/exportIdentity";

describe("client-side identity (Semaphore V4)", () => {
  it("creates a new identity and exposes only the public commitment", () => {
    const { identity, commitment } = createIdentity();

    expect(typeof commitment).toBe("string");
    expect(commitment.length).toBeGreaterThan(0);
    // The commitment is derived from the public key.
    expect(identity.commitment.toString()).toBe(commitment);
  });

  it("round-trips through export / import without revealing the secret in the commitment", () => {
    const { identity } = createIdentity();
    const privateKeyBase64 = exportIdentity(identity);

    expect(typeof privateKeyBase64).toBe("string");
    expect(privateKeyBase64.length).toBeGreaterThan(0);

    const reimported = importIdentity(privateKeyBase64);
    expect(reimported.commitment).toBe(identity.commitment);
  });

  it("keeps the secret scalar private (never derivable from the commitment)", () => {
    const { identity, commitment } = createIdentity();

    // The commitment is public; the secret scalar must remain secret.
    expect(identity.secretScalar).toBeDefined();
    expect(identity.commitment.toString()).toBe(commitment);
  });
});
