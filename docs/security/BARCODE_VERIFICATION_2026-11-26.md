# Barcode identification implementation and verification — 26 November 2026

## Scope and preservation

Continued the interrupted implementation in `C:/Users/User/pos_app`, starting with six modified tracked files and four new source files. Preserved the shared catalogue, richer metadata, policy card and approval services rather than restarting. No production deploy, rule deploy, Git push or live Firebase data operation was performed.

## Original failing test

Baseline: 252 passed, 1 failed. The failing case was `FirestoreCommunityCatalog shares name, category, image and price, never stock, then finds it` (`test/catalog/community_catalog_test.dart`). Initial contributions redundantly wrote `priceAt` in addition to `createdAt`, violating the exact document-shape assertion. Creation now uses `createdAt`; a price added later uses `priceAt`. The shape assertion remains exact. A separate privacy assertion was strengthened to require an anonymous contribution marker and reject the contributor UID in public values.

## Completed work

- Retained the official Open Facts universal API (`product_type=all`), which redirects to Open Food, Beauty, Products and Pet Food Facts, plus shared ShopPad lookup and the no-key UPCitemdb trial fallback.
- Name, image, category, brand, size and description are displayed and preserved. Added editable brand/size/description fields to the existing owner product editor without replacing the design.
- External offers retain their original currency and are explicitly reference-only. They never populate a cashier selling price or get converted into a Bahrain price.
- Added free-tier UPC request throttling, keeping cache/deduplication and manual entry fallback.
- Connected unknown-barcode cashier UI to approval requests and the owner requests sheet in Products. Owner approval atomically adds the product and removes the request. Decline/load errors are visible.
- Default policy remains deny sale until owner approval. An owner may enable shared-reference-price sales with a price ceiling. The actual shared price and policy are reread and revalidated at submission.
- Corrected the interrupted draft so a cashier reference-price sale creates no permanent inventory. It uses one separate receipt, with an audit marker, without discounts. Its stable receipt ID retains synchronization/idempotency behavior.
- Added atomic per-store barcode claims for editor saves, owner approvals, import and recovery. Existing product IDs and historical receipt links remain intact. Import batches respect Firestore rule document-access limits.
- Added Arabic translations and 320px English/Arabic identification tests. Kept Save and Cancel visible while the expanded product form scrolls.
- Catalogue writes reject explicit store identifiers, stock, costs and private account fields. New entries use a non-identifying contributor marker. Reads of old UID-bearing entries are denied rather than exposing their IDs across stores.

## Verification

| Check | Final result | Evidence and boundary |
| --- | --- | --- |
| `flutter analyze` | PASS, no issues | Final analysis after the UPC/EAN normalization fix. |
| Complete `flutter test` | PASS: 268 passed, 0 failed | Covers existing Owner/Cashier permissions, checkout, stock corrections, receipts, queued synchronization, reports, recovery and Arabic/English regressions. No tests deleted or skipped. |
| Strengthened owner form tests | PASS: 10 passed, 0 failed | Existing suite rerun after adding assertions for brand/size/description autofill and manual editing, including parent-route replacement. These are not 10 additional tests on top of the full suite count. |
| Firestore Emulator security | PASS: 34 passed, 0 failed | Store/account isolation, permissions, approvals, immutable receipts, exact reference price, revoked policy, forged request prices, privacy, atomic barcode uniqueness and a real five-product import batch. |
| Live catalogue service probes | PASS: 4 passed, 0 failed | Real HTTP product responses for Open Food Facts, Open Beauty Facts and Open Products Facts. The UPCitemdb probe forces only the preceding Open Facts miss and then uses the real free UPC API; it is a controlled fallback integration test, not proof that every barcode resolves. |
| Existing browser bootstrap test | PASS: 1 passed, 0 failed | Versioned bundle loading preserves browser storage. |
| Existing Semgrep configuration | COMPLETED: 15 rules, all 88 Dart source files, 0 ERROR findings, 3 WARNING findings | Includes new untracked source files. See reviewed warnings below. |
| `git diff --check` | PASS | No whitespace errors. |
| Local release `flutter build web --release --no-wasm-dry-run` | PASS | Final bundle built successfully; no upload or deployment. A non-fatal CupertinoIcons font-asset warning remains for device visual review. |

Logs are retained in `C:/Users/User/OneDrive - University of Bahrain/Documents/ChatGPT/pos_app/`, outside the application repository. Machine-readable Semgrep results and the live probe harness are in the ignored `.security-audit` directory. Firestore attack tests use only `demo-shoppad-security` at localhost. Port 9180 was used because 9080 was already occupied; no existing service was stopped.

### Reviewed static warnings

1. `lib/firebase_options.dart:50` — public web Firebase API configuration key.
2. `lib/firebase_options.dart:61` — public Android Firebase API configuration key.
3. `lib/screens/profile/profile_screen.dart:592` — the log includes the word `email`, which triggers the generic detector, but its value is a Firebase error **code** or exception type, not the email address.

No suppressions or weaker security scan rules were added. The release build also emitted a CupertinoIcons font-asset warning; it did not fail compilation. A physical-device visual review remains necessary. Public Firebase client keys are not administrative secrets; server rules remain essential. These findings do not prove that every possible security defect has been excluded.

### Additional defect found by live testing

Open Facts normalizes some UPC-A identifiers to EAN-13 by adding a leading zero. The previous strict string comparison rejected the real response. It now accepts the numerically equivalent zero-prefixed representation while retaining the original scanned code and still rejecting a different identifier. A regression test covers this case. Product identity is not inferred from a name or image.

### Reproduction commands

Run from the actual application root, `C:/Users/User/pos_app`:

```powershell
flutter analyze
flutter test --reporter expanded
node --test test/web/web_bootstrap.test.cjs
semgrep scan --metrics=off --no-git-ignore --config .semgrep/dart-security.yml lib
```

With Java 21 or newer on PATH and the standard port free:

```powershell
$env:JAVA_TOOL_OPTIONS='-Duser.language=en -Duser.country=US'
firebase emulators:exec --only firestore --project demo-shoppad-security 'node --test test/security/firestore_rules.test.cjs'
```

The tests hard-code the demo project and localhost. `SHOPPAD_EMULATOR_PORT` optionally selects another local port; it cannot change the host or project. The final verification used an ignored configuration file with port 9180 and the same root `firestore.rules`.


## Important limits and submission boundaries

- Coverage spans retail categories; no free catalogue guarantees every barcode, correct metadata, an image, or a local selling price. Source data remains editable and needs review. In the live probes, different catalogues returned different product descriptions for the same sample UPC, illustrating why source information is a suggestion rather than an independently verified identity.
- UPCitemdb explicitly returns `Access-Control-Allow-Origin: https://www.upcitemdb.com`. The web build therefore skips direct UPC fallback. Native clients use its free endpoint. No unofficial proxy or paid backend was added. Official Open Facts sources work cross-origin in the read-only probes.
- Unknown shared-price products are sold separately, without discounts or permanent stock changes. Normal registered products retain their existing checkout and stock-update path.
- Reference-price authorization is checked again during synchronization. Revocation or a changed price leaves an accepted pending receipt in conflict for review; it must not be silently repriced or duplicated.
- Atomic claims protect new app writes and competing edits. Legacy products predate claims. The app checks legacy duplicates before saving; comprehensive protection against a deliberately modified owner client duplicating an unclaimed legacy record requires an owner-authorized one-time claim backfill. No live migration was run.
- Older public catalogue entries containing contributor UIDs are hidden by the new rules. A separately authorized privacy migration can anonymize them later. No live catalogue was changed.
- Existing receipt rules are not a full trusted financial calculation engine for arbitrary legacy multi-line receipts. The new single-item reference workflow is checked explicitly. Commercial-grade validation of every normal sale line still needs a trusted transaction service or a separately scoped comprehensive rules redesign.
- Tests using fake Firestore validate application behavior; only Emulator tests validate security rules. Real-device camera, printing/sharing, browser permission prompts and a complete physical retail session have not been independently re-tested in this takeover.
- The new application changes and rules form a matched local release. The previously hosted app/live rules were not updated, as requested. Do not expect the old hosted URL to demonstrate these new workflows.

## Provider documentation

- Open Facts universal lookup: https://openfoodfacts.github.io/documentation/docs/Product-Opener/v3/products/get-api-v3-product-code/
- Open Facts product categories: https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/scanning-cosmetics-pet-food-and-other-products/
- UPCitemdb free limits: https://www.upcitemdb.com/wp/docs/main/development/plan/


## Submission assessment

The local implementation and automated evidence are ready for review. This is **not** an unconditional production or physical-device readiness certification. The browser UPC restriction, legacy claim/privacy migration boundary and remaining device checks above must be acknowledged in the submission. The existing hosted URL still has the previously deployed application/rules. Any future deployment must ship the matched application and rules together under a separate authorization.
