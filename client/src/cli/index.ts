#!/usr/bin/env tsx
/**
 * NightShield client CLI entry point.
 *
 * Demonstrates the anonymous voting flow. Identity creation and proof generation
 * happen entirely client-side. The identity secret never leaves this process.
 *
 * Usage:
 *   npx tsx src/cli/index.ts create-identity
 */

import { createIdentity } from "../identity/createIdentity";
import { exportIdentity } from "../identity/exportIdentity";
import { importIdentity } from "../identity/importIdentity";

async function main() {
  const [command] = process.argv.slice(2);

  switch (command) {
    case "create-identity": {
      const { identity, commitment } = createIdentity();
      console.log("Identity created locally.");
      console.log("Commitment (public):", commitment);
      console.log(
        "Back up this private key (never share it):",
        exportIdentity(identity)
      );
      // Round-trip check
      const reimported = importIdentity(exportIdentity(identity));
      if (reimported.commitment !== identity.commitment) {
        throw new Error("identity round-trip failed");
      }
      console.log("Identity import/export round-trip verified.");
      break;
    }
    default:
      console.error("Unknown command. Use: create-identity");
      process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
