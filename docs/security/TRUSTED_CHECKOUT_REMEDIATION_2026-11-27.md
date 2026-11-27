# Trusted checkout remediation — 27 November 2026

## Activation status
Implemented and verified locally. No live rules, customer data, production hosting, preview hosting, billing plan or Git remote was changed by this remediation. The existing public app still uses the previously deployed rules and does not yet have these protections activated.

Activation requires an authorized HTTPS Node host and server-side Firebase credentials/identity. The user was asked whether such a free host exists or local preparation is preferred. No host endpoint was provided. Publishing the new restrictive rules before the server and matching client are available would block cashier checkout. The Flutter production entry point now uses the new trusted gateway; a missing endpoint fails closed and keeps pending receipts, rather than falling back to direct Firestore writes. A separate build output is used so the last preview artifact is not silently replaced.

## Implemented
- `server/checkout.cjs`: trusted atomic checkout; active verified store membership, actual owner binding, canonical product unit prices/barcodes, validation of every line (including unknown products at any position), owner-authorized shared prices, current VAT behavior, calculated amounts/corrections, 100 distinct product lines, inventory updates and immutable receipt creation in one transaction.
- Stable request digest and legacy receipt comparison preserve idempotent retries and do not deduct stock twice after a lost acknowledgement.
- Owner cost snapshots and derived offer labels/invoice formats retained. Cashier cost injection ignored. Unknown products never enter permanent inventory.
- `server/index.cjs`: SDK ID-token validation with disabled/revoked-user checking, exact origin allowlist, bounded JSON body, noncached responses and generic internal errors. Privileged credentials stay on the server.
- `TrustedSaleGateway`: sends authenticated intents over HTTPS, checks receipt identity and completion, protects account switching and retains retry/review semantics. No direct client fallback.
- Firestore rules deny direct cashier receipt and checkout-stock writes. Owner inventory administration/refunds/backups and authorized stock adjustment remain available. The owner remains the trusted administrator of their own store.
- Existing cashier manual discounts remain supported and explicitly recorded, up to the subtotal. A manual discount is an existing permission, not an arbitrary unit-price override. No payment-provider or cash-receipt authenticity is claimed.

## Verification
- Full Flutter suite: 287 passed, 0 failed (includes 6 new trusted-gateway tests).
- flutter analyze: no issues found.
- Release web compilation succeeded in isolated `.security-audit/trusted-web-build` output; not deployed and intentionally unconfigured until a real endpoint is supplied.
- Firestore Emulator client security suite: 36 passed, 0 failed. The previously accepted direct-write shapes now require denial; existing permissive assertions were strengthened, not removed. Legitimate server acceptance is verified in the server suite.
- Auth + Firestore Emulator server suite: 23 passed, 0 failed. Includes an actual SDK-verified Auth emulator token through the HTTP endpoint; forged token rejection; original attack cases; unknown item at position 100; wrong store/account; price changes; duplicate/concurrent retries; competing sales of the last unit; manual discounts/bundles; VAT registered, unregistered and legacy unset registration; buyer invoice format; stock correction; owner-only costs; legacy retries; offline timestamps; 100 distinct product transaction; CORS and internal-error masking.
- Follow-up real Auth emulator check: disabling the authenticated account rejects its existing token (HTTP 401) without further stock deduction.
- npm audit: 133 server dependency entries, 0 reported vulnerabilities at scan time.
- Semgrep: 90 Dart files, same 3 reviewed WARNING findings (two public Firebase configuration keys and a code-only error logging heuristic), 0 ERROR findings.
- No pending receipt migration, deletion or live data write was performed.

## Remaining requirements and limits
- The deployment host/HTTPS endpoint and coordinated activation are still required. This is not fixed on the live link yet.
- Local IndexedDB/Sembast receipts remain unencrypted by the app. Safe device encryption needs a separate key/unlock/recovery and migration design. A hard-coded encryption key would not solve the privacy risk.
- App Check, host-level rate protection and operational monitoring need deployment configuration. Do not automatically enable a paid plan.
- Tests do not prove the absence of every vulnerability, compromised-device access or actual cash/bank payment. Real hosted endpoint and physical-phone/offline tests must follow activation.

See `server/README.md` for the exact setup and safe activation sequence.
