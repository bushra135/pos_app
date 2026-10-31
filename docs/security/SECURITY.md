# ShopPad security status

## Access control

The root `firestore.rules` is the authoritative rule source. The previous live rules allowed unrestricted database access until May 2027. The replacement denies anonymous access and unknown collections, requires verified email for store data, isolates stores and locks account role/store identifiers.

Owner identity is bound to `stores.ownerUid`; setting `users.role` in a client cannot claim another store. New owner profile/store creation is atomic. New cashiers remain pending until their owner approves them. `onDuty` is an availability flag, not permission to activate an account. Existing approved cashier accounts retain access.

Approved cashiers can edit existing catalogue details (including price, stock and images) in their own store, as required by the product workflow. They cannot move products between stores, edit other stores, approve themselves, read other cashiers' receipts or rewrite completed receipts. Catalogue edits cannot rewrite sale-linkage/correction audit fields. Checkout stock/audit writes still require a linked new receipt in the same transaction and cannot increase inventory. Approved store members can delete products from their own store; saved sales remain immutable. Product creation remains owner-only. This does not cryptographically establish that cash was actually paid or prove every client-supplied line/total is honest; high-assurance financial validation needs a trusted server transaction endpoint.

Backups are owner-only. Completed copies are immutable. Restoring missing store records remains supported.

## Transport, storage and secret handling

Firebase services use HTTPS/TLS and Firestore provides server-side encryption at rest. These are provider-managed protections, not end-to-end encryption. See https://cloud.google.com/firestore/native/docs/server-side-encryption and https://firebase.google.com/docs/projects/api-keys.

Firebase client configuration is public by design. It is not an admin credential. The Firebase CLI's privileged login remains outside the app bundle. Secret environment files, private-key files and local security snapshots are excluded from Git. The current app has no paid AI provider key.

**Local pending receipts and the cached catalog are not encrypted by this app.** Browser IndexedDB, native Sembast files and Firebase's persistent caches require a separately designed local encryption/key-recovery policy. Do not claim AES protection or end-to-end encryption for those files. A fixed key shipped in Dart/JavaScript or `.env.local` would not solve this.

Do not delete browser storage while receipts are pending. Encryption migration must preserve existing pending receipts and provide unlock/recovery, ideally using platform-protected keys on native devices and a user-held secret for browser storage.

## Browser and account hardening

Hosting adds anti-framing, MIME-sniffing protection, origin-only cross-site referrer policy and camera-only permissions. The CSP currently restricts embedding, base URLs and object content; it is not a complete script-source policy. Account changes are observed live. Unknown/disabled/pending roles do not enter owner/cashier screens. Password values are no longer copied into verification-route drafts. Login/reset messages avoid exposing whether an account exists. Server-side email-enumeration protection is enabled. Firebase enforces a 12-character mixed-case/numeric/symbol policy on new/changed passwords; existing sign-ins are not forced to upgrade.

## Verification and remaining work

Local Firestore attack tests live in `test/security/firestore_rules.test.cjs` and use only the hard-coded demo emulator. Run an emulator on `127.0.0.1:9080` with project `demo-shoppad-security`, then run `node --test test/security/firestore_rules.test.cjs`. Java emulator processes on Arabic Windows should use `-Duser.language=en -Duser.country=US`.

Test cases cover store isolation, anonymous/unverified requests, role escalation, account approval, receipt mutation, transaction stock changes, owner registration and backup immutability. Flutter regression tests remain separate. Fake Firestore tests alone do not validate deployed rules.

App Check is not configured or enforced; add a registered provider and monitor legitimate requests before enforcement. App-level MFA is not configured. Enable strong MFA for the administrative Google/Firebase account independently. The two app API keys are restricted to six required Firebase services, retaining the existing browser and Android restrictions. Review these when adding services or domains. Rules, tests and encryption are layers, not a guarantee that no breach is possible.

## Verified deployment — 2026-10-31

The tested root rules were deployed to shoppad-f3d43. The live source was compared with the local source. An unauthenticated production products request was denied, the preview bundle matched the built app, browser protection headers were present, and the restricted browser API key still reached Authentication with generic credential errors. No live customer records were modified by those probes.
