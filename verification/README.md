# Local Flutter-to-server acceptance

This opt-in suite exercises the actual Dart `TrustedSaleGateway` and durable Sembast file queue against the actual Node checkout handler, Firebase Admin SDK, Auth Emulator and Firestore Emulator. It uses only project `demo-shoppad-security` on fixed localhost emulator ports. It does not deploy anything.

Requirements: Flutter on PATH, Node 22+, Firebase CLI, supported Java, and `npm ci --prefix server`. Stop other processes using ports 9184/9197/4404/4504 before running; do not stop unrelated user services automatically.

From the repository root:

```sh
firebase emulators:exec --config firebase.verification.json --only firestore,auth --project demo-shoppad-security "node verification/run_checkout_emulators.cjs"
```

On Windows, if Flutter is not on PATH, set `SHOPPAD_FLUTTER_COMMAND` to the existing Flutter batch executable first. Do not supply production credentials. Auth tokens and an ephemeral receipt signing key are generated only for the emulator run; tokens are passed to the test process through its environment rather than printed or saved.

The launcher clears only the named demo emulator documents, creates synthetic users/products, starts a loopback HTTP server and runs the five Dart acceptance tests. The tests verify a disk queue reopen, cashier/owner sale, signed-receipt verification, duplicate retry, lost acknowledgement, price-tampering rejection and forged-token rejection. The launcher independently checks exactly three confirmed receipts and the final stock of seven from an initial ten.

These files are outside `test/` so the ordinary Flutter unit/widget suite remains runnable without starting emulators. Run this explicit command separately; do not mark an unavailable emulator run as passed. The test refuses missing or non-local configuration. The launcher also requires an anonymous product read to be denied, refusing accidentally permissive emulator rules. No browser/physical-phone or hosted-endpoint result is implied by this acceptance suite.
