# ShopPad — Security, privacy and reliability review

Date: 27 November 2026 (Asia/Riyadh).
Scope: current local Flutter source and Firestore rules, compiled web bundle, demo Firebase Emulator attack probes, dependency advisories, and read-only public preview checks. No production data writes, rule deployment, Hosting deployment, or Git push were performed during this review.

## Verdict
Two high-priority financial-integrity vulnerabilities were reproduced against the local Firestore rules. Passing the existing regression/security suites does not establish that hostile clients cannot bypass the UI. Suitable for a supervised academic demonstration with test data; not recommended for unattended real financial operation until these findings are resolved and retested.

## Confirmed findings

### HIGH — ordinary receipts accept client-chosen prices and no inventory deduction
Location: firestore.rules, sales create rule; lib/services/sale_gateway.dart.
Precondition: authenticated, verified, approved cashier in their own store. No anonymous access or cross-store read was required.
Reproduction: demo product productA priced at 2, stock 3. A direct authenticated receipt-only write used unit price/subtotal/total 0.01, discount 0. HTTP 200; product stock remained 3.
Impact: misleading sales totals/receipts and inventory inconsistency. The total arithmetic checks do not compare individual item prices against authoritative inventory or require the corresponding inventory update. UI transaction validation is bypassable by a custom client. This does not demonstrate access to another store.
Recommendation: validate every line, price/offer/tax policy, quantities, stock deltas and receipt identity in a trusted transaction boundary. If using Firestore rules, enforce equivalent invariants for every supported line and restrict client-writable aggregate fields. Preserve legitimate discounts, offline retries, correction audit, owner backups and VAT behavior. Add rejection tests for receipt-only, underpriced, foreign-item and mixed unknown-item writes.

### HIGH — unknown-product price authorization checks only the first line
Location: firestore.rules, sales create rule and validUnknownSale.
Reproduction: store policy absent/disabled; send a receipt with a normal first line and an unknown_A_12345678 second line priced at 0.01, omit unknownBarcode. HTTP 200.
Impact: a modified authenticated cashier client can include an unapproved unknown product at an arbitrary price despite the application UI enforcing a separate single-item authorized sale.
Cause: normal-sale branch inspects only items[0]; the second item never enters validUnknownSale.
Recommendation: prevent any unknown line from entering the normal path and enforce the dedicated single-item owner-authorized policy at the trusted boundary. Checking the UI or first item is insufficient.

### MEDIUM — device copies are not encrypted by the app
Location: lib/services/platform/local_pos_database_web.dart and local_pos_store.dart.
Pending receipts, cart state and product cache use IndexedDB/Sembast without an application encryption codec. Account/store scoping is useful application isolation, but is not encryption against a person or malicious script with access to the browser/device storage. Do not clear storage while sales are pending. Any encryption migration needs key handling, account-switch behavior, recovery and preservation of unsynchronized receipts.

### Hardening / privacy limitations
- App Check is absent from the app integration. It can reduce scripted abuse but does not repair authenticated financial authorization.
- Preview response has HSTS, anti-framing, nosniff, referrer and camera permissions headers. CSP restricts framing/objects/base URLs, but does not implement a complete script-source policy. No XSS exploit was demonstrated in this review.
- Shared catalogue fields (product metadata, image and reference price) are intentionally shared across active stores. Store identity, stock and cost fields are rejected by the existing tests. A shared price is community-contributed, not a verified universal retail price.
- Arbitrary HTTPS product-image URLs may contact external image hosts. These hosts can receive normal image-request network metadata. No server-side image proxy/SSRF was found in the inspected flow.

## Verification results
- flutter analyze: no issues found.
- Flutter full suite: 281 passed, 0 failed. Includes checkout, duplicate receipt handling, stock updates/corrections, synchronization state, local pending sales, backup and owner/cashier workflows. Automated tests do not replace physical-phone/network-loss testing.
- Firestore baseline security suite: 35 passed, 0 failed in demo-shoppad-security. Covers anonymous/unverified access, store isolation, role escalation, approvals, immutable receipts, stock/audit links, private costs, backups, barcode claims, shared metadata privacy, unknown-product permissions and own profile photos.
- Additional exploit reproductions: 2 confirmed accepted requests (HTTP 200). The probe harness deliberately asserts acceptance to preserve evidence; these are confirmed findings, not security passes.
- Semgrep: 15 rules, 89 Dart files, 3 WARNING findings, 0 ERROR findings. Two are public Firebase client API keys; the third flags an existing error-code-only password-reset log. No warning was hidden or suppressed.
- Secret pattern scan: 201 tracked/unignored text files; no private key/service-account/AWS/provider-secret/GitHub-token pattern matches. Compiled main.dart.js separately scanned with no matching secret patterns. Firebase client API keys remain public configuration. This was not a Git-history or whole-device credential audit.
- Dependencies: 132 hosted Pub packages/locked versions queried through OSV querybatch; no known advisory matches returned at scan time. This is not proof of zero dependency vulnerabilities.
- Live read-only anonymous products request: HTTP 403 (denied).
- Live preview headers: HSTS, X-Frame-Options DENY, X-Content-Type-Options nosniff, restricted Permissions-Policy and partial CSP present.
- Read-only live Firestore source comparison: current deployed source matches the locally tested rules after normalizing line endings. The initial cached token returned HTTP 401; a normal Firebase CLI credential refresh allowed the read-only comparison. Ruleset: 27be017e-6343-47c7-9624-7dcf3a95cd69. No authenticated exploit was sent to the live database. Thus the reproduced rule weaknesses also apply to the deployed source; no live customer data was modified.

## Evidence
Local ignored files under .security-audit/review-20261127-* contain emulator logs, the isolated exploit script, secret scan counts, OSV results, Semgrep output and read-only response headers. No private credential values are included in this report. The demo exploit script is hard-coded to localhost and demo-shoppad-security.

## Next steps
Resolve both high-priority financial integrity findings, add hostile-client rejection regressions, then rerun all baseline tests and exploit probes. Plan local storage protection separately. No automatic live rules or architecture changes were made: this request was an audit, and safe fixes must preserve checkout/offline/VAT/backup behavior.
