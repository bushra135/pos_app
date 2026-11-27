# Scan feedback and digital receipt seals — 27 November 2026

Status: local implementation, not deployed. The trusted checkout backend still needs an authorized HTTPS host, server credentials and persistent signing-key configuration. Publishing the changed Flutter build without that endpoint would leave secure checkout unconfigured; publishing only restrictive rules would block cashier checkout. No live data/rules/hosting/billing changes were made.

## Barcode sound
- A short beep is emitted for each accepted decode, including unknown products, before lookup finishes. Held duplicate camera frames and full queues do not trigger repeated beeps. Intentional repeat scans beep again.
- Browser camera and owner one-shot scanner use Web Audio. Login/navigation pointer/keyboard gestures unlock audio for mobile browser policies. Pulses are scheduled separately for quick scans and disconnected afterward; audio failure never blocks scanning.
- Native/keyboard feedback uses the existing beep asset through a reusable AudioPool. Owner product-camera reads also use it. Lookup failures use haptics without adding duplicate beeps.
- The browser scanner URL is versioned for the next deployment. No physical iPhone/Android speaker test was performed; OS volume/mute and browser restrictions can still suppress sound.
- Existing JS permission test had a stale assertion expecting a raw error name; it now asserts the complete existing user-facing permission guidance. No camera behavior was weakened.

## Digital seal
- Ed25519 signatures are issued only after trusted server validation, in the same receipt/stock transaction. Private keys are host-only, never embedded in the app. Public-key rotation preserves old signatures.
- The seal binds invoice and item contents, amounts, buyer/cashier/store details. A protected per-receipt nonce prevents public guessing of private fields from the digest. The public QR carries minimal merchant/reference/date/amount metadata plus an opaque digest and signature, no buyer/cashier identity or store code.
- Verification checks the signature and authoritative stored receipt, and returns only minimal public receipt metadata. Tampering, unknown issuers, missing records and invalid signatures are rejected.
- The bilingual verification page escapes all display values and sets no-store, no-referrer, anti-framing and restrictive script-free CSP headers.
- The app loads only server-confirmed matching proofs from the configured trusted host. PDF export renders the canonical saved receipt with a verification QR. Pending/unsigned receipts never receive an authenticity mark.
- An authentic QR can be copied onto a fake document; users must compare the amount/reference/date/merchant shown by the trusted verification page. This cannot prove cash/payment or stop exact copies of an original receipt. It is not a qualified legal seal.

Evidence logs are in ignored .security-audit/scan-audio-*, sound-seal-* and receipt-seal-* files. Signing tests use ephemeral in-memory keys; no production signing key was created.

## Final verification
- Complete Flutter suite: 291 passed, 0 failed.
- Auth/Firestore server suite: 31 passed, 0 failed, including transaction-issued seals and tamper/privacy cases.
- Browser scanner/sound suite: 10 passed, 0 failed.
- flutter analyze: no issues.
- PDF seal rendering and ordinary receipt export: passed; the PDF library still emits a Courier Unicode warning during the receipt export test. A physical printer/phone test was not performed.
- No deployment or privileged production key generation.

- Release web build succeeded in isolated `.security-audit/sound-seal-web-build`; not published. Build retained the existing missing Cupertino font warning.
