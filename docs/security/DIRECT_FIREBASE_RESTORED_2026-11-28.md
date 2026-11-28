# Direct Firebase checkout restored — 28 November 2026

The user explicitly cancelled separate-server checkout and the digital receipt seal after the deployment dependency and tradeoff were explained. This supersedes the activation recommendations in the earlier trusted-server reports for the active application.

## Active application

- `lib/main.dart` again constructs `FirestoreSaleGateway`. No `SHOPPAD_CHECKOUT_URL`, Render account, backend signing key or privileged Firebase server credential is needed to use checkout.
- The existing direct Firestore transaction, durable local receipt queue, retry/idempotency checks, store isolation, owner/cashier permissions, product catalogue, stock handling, VAT invoices, Arabic/English UI and recent design changes are retained.
- The receipt screen no longer loads/displays the server verification panel. Normal PDF exports no longer call the server seal verifier. Existing optional verification utilities and their tests are retained as inactive code rather than erased.
- Local `firestore.rules` restores only the separate-server migration (commit `55231bb`) to its immediate previous rules. An exact read-only comparison confirmed this restored file matches the currently deployed rules. No rule deployment is needed or performed by this change.
- The `server/` and opt-in trusted-server verification files remain for reference; they are not required by the active application.

## Security boundary

This is a functional rollback, not an equivalent replacement for trusted server validation. The independent 27 November review demonstrated that the original rules allow an approved malicious cashier to submit an underpriced receipt-only write or hide an unknown item after a normal first line. Direct Dart gateway checks protect normal application flows but a modified client can bypass them. Store isolation and ordinary access restrictions remain; these facts do not eliminate the financial-integrity findings.

The current stricter server-architecture rule tests have deliberately not been deleted, weakened or suppressed. Their results must be distinguished from the historical direct-architecture baseline when reporting verification. Any server-only denial expectation that fails after this rollback is not evidence of equivalent security. Do not claim that the application is free from vulnerabilities or suitable for unattended commercial financial use.

## Deployment scope

Only Firebase Hosting preview channels are authorized for update. Do not publish to the live channel, change billing, push Git, deploy rules or write live store data as part of this rollback. Preserve the earlier working preview until the rebuilt direct-checkout app passes the Flutter regression suite and matches the published bundle.


## Verification results

- Complete Flutter suite: 299 passed, 0 failed (`.security-audit/direct-firebase-flutter-tests.log`).
- Flutter analysis: no issues found (`.security-audit/direct-firebase-analyze.log`).
- Release web compilation: passed (`.security-audit/direct-firebase-web-build.log`), retaining the previously recorded Cupertino font-family warning.
- Historical pre-server rule suite, executed without changes: 35 passed, 0 failed (`.security-audit/original-direct-security.log`).
- Current trusted-server rule suite, kept unchanged: 31 passed, 5 failed (`.security-audit/current-server-security.log`). Four failures concern the intentional removal of server-only denial semantics for legitimate transactions, offers and authorized reference pricing. The fifth includes the known underpriced receipt-only/hidden-unknown attack cases; that security limitation remains real. No failure was suppressed or represented as passing.
- Read-only live rules comparison: restored local rules match deployed rules (`.security-audit/direct-live-rules-check.json`). No live rules were changed.

These are local/regression/emulator results. No real store sale or stock update was submitted to the live project during verification.
