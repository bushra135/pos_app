# ShopPad local readiness — 28 November 2026

## Scope and status

Hosting was explicitly deferred by the user. No hosting deployment, live rule update, billing change, Git push or live store write was performed in this pass.

The local app and server compile/test successfully within the coverage below. This is local verification, not production readiness or a claim that every vulnerability has been eliminated. The public preview has not received these changes. The current Flutter entry point requires `SHOPPAD_CHECKOUT_URL`; without the trusted endpoint it fails closed instead of using the old direct-write checkout.

## Corrected in this pass

Flutter Web sends an OPTIONS preflight before its cross-origin JSON POST to `/verify`. The server previously returned 405, preventing a browser from reaching receipt-seal verification even though ordinary HTTP POST tests passed. A new regression reproduced 405 instead of 204 before the fix.

`server/index.cjs` now answers verification preflight after the existing exact-origin allowlist check, with Content-Type and the supported verification methods. Preflight does not authenticate, read receipts or execute checkout. Disallowed origins still return 403; missing routes return 404; unsupported verification methods return 405. Receipt signatures and canonical stored-receipt validation remain unchanged.

## Verified results

- Complete Flutter suite: **299 passed, 0 failed**, including the receipt bilingual/direction guard. This completed earlier on 28 November; no Dart files changed in this pass. Log: `.security-audit/final-ui-regression-tests.log`.
- Flutter analysis: **no issues found** in that same verified Dart source. Log: `.security-audit/final-ui-analyze.log`.
- Server HTTP suite: **5 passed, 0 failed**, including the new preflight regression. Before/after logs: `.security-audit/receipt-cors-before.log`, `.security-audit/receipt-cors-after.log`.
- Complete server suite with Auth and Firestore Emulators: **32 passed, 0 failed**. Tests cover trusted checkout, actual Auth emulator tokens, rejection cases, stock transactions, retries, signatures and HTTP behavior.
- Firestore rule suite on the dedicated demo emulator: **36 passed, 0 failed**. No production project data was used. Combined log: `.security-audit/final-server-security-20261128.log`.
- Server `npm audit --omit=dev`: **0 reported vulnerabilities** at scan time. Log: `.security-audit/final-server-audit-20261128.json`.
- Existing custom Dart Semgrep rules: **96 files, 15 rules, 0 ERROR findings, 3 WARNING findings**. Two warnings identify client Firebase configuration keys; these are not privileged Admin credentials. The third identifies reset-email logging, which records only an SDK error code/type, not the email or full exception. No findings were hidden or suppressed. Output: `.security-audit/final-semgrep-20261128.json`.
- Release Flutter web compilation: **passed**. Local output: `.security-audit/submission-web-20261128`; log: `.security-audit/submission-web-20261128.log`. The compiler emitted a Cupertino icon-family warning; application source contains no explicit CupertinoIcons usage. No iPhone rendering claim follows from compilation alone.
- Arabic/English receipt rendering and numeric direction were visually checked during the preceding receipt work. Current pass did not change receipt layout.

## Remaining activation and testing boundaries

- Deploy and configure a trusted HTTPS backend, then test the real hosted endpoint before coordinating matching rules/client activation. Do not publish restrictive rules alone or remove fail-closed behavior.
- The new preflight regression exercises real local HTTP requests and browser-required CORS headers. It is not an actual hosted-browser acceptance test.
- Physical-phone camera/audio/printing, repeated real-device cold starts, and real hosted offline reconnect/checkout need device acceptance testing. Unit/widget/emulator tests do not replace that evidence.
- Local Sembast/IndexedDB receipt storage is not encrypted by the app. Device unlock, key recovery and pending-receipt migration need a separate design before claiming encryption.
- App Check, host rate controls, monitoring and signing-key management require deployment configuration.
- Financial tests establish supported application invariants under their fixtures; they do not prove physical payment occurred or guarantee absence of undiscovered vulnerabilities.

Earlier detailed security reports remain in this directory. This report records the latest local counts and does not imply that the existing public preview uses the new trusted checkout.


## Follow-up: actual Flutter-to-server acceptance

After hosting was deferred again, five additional opt-in acceptance tests were added under `verification/`. They run the production Dart gateway and real durable Sembast file storage against the actual Node checkout handler, Firebase Admin SDK, Auth Emulator and Firestore Emulator. They are separate from the 299-test unit/widget suite.

- Cashier receipt survives closing and reopening its local database, then confirms using a real Auth-emulator token.
- Repeating the same confirmed intent creates no duplicate receipt or stock deduction.
- The owner can sell through the same trusted endpoint.
- A modified unit price and forged token cannot create a receipt or change stock.
- A deliberately lost HTTP acknowledgement leaves the queued receipt durable; retry confirms without another deduction.
- The stored server signature verifies through the real verification HTTP route.
- The launcher independently checks exactly three confirmed signed receipts and final stock 7 from initial stock 10.

Result: **5 passed, 0 failed** using the portable `firebase.verification.json` configuration and real repository Firestore rules. The launcher explicitly requires anonymous product access to return 403 before running, so an emulator that silently falls back to permissive rules cannot count as a pass. The test project and localhost emulator addresses are asserted before setup; production credentials are not used. See `verification/README.md` for the tested command. Log: `.security-audit/portable-acceptance-20261128.log`.

Initial harness failures (module import, a future-dated synthetic receipt, and portable emulator rules-path resolution) were corrected in the harness; production date validation and assertions were preserved. A preliminary portable run without loaded rules is not counted as acceptance evidence; the final guarded run above loaded the actual rules and passed.

The updated application, including the soft-blue account header, also compiled successfully to `.security-audit/app-ready-20261128` (log: `.security-audit/app-ready-20261128-build.log`). Full Flutter analysis including the new verification Dart file reported no issues (log: `.security-audit/local-completion-analyze-20261128.log`). The same Cupertino icon-family compilation warning remains; physical-iPhone rendering still needs acceptance testing.

This proves local HTTP/SDK/storage integration for these cases, not physical-phone UI behavior, browser IndexedDB restart behavior or a hosted HTTPS deployment. No preview, live rules, billing configuration or store data was changed.
