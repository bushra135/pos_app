# Owner Home onboarding initialization fix — 26 November 2026

## Reproduced cause

`AuthWrapper` waits for Firebase Authentication, email verification and the user profile before selecting Owner Home. `main` initializes Firebase and the synchronization service first. `OwnerHomeScreen._loadOwnerData` then loads the profile/context and sets `isLoading = false` before `_loadDashboardData` finishes its store, cashier and product reads. The checklist previously used the dashboard's initial `totalProducts = 0` and `cashierCount = 0`. The OR condition therefore built the checklist immediately, even though the configured store had not yet been read. Initializing the two payment/VAT booleans to true did not fix those zero counts.

A controlled widget regression failed against the original implementation while `stores/READY` was held pending: the `Get your store ready` Text widget was present. The before-fix failure log is preserved in the task workspace as `onboarding-before.log`.

## Correct state and data ownership

The checklist now has a separate immutable readiness snapshot. Null means unknown, not incomplete. It is established only after the store document, cashier query and product query have all returned server-confirmed snapshots without pending writes. Dashboard cache/default values are not checklist inputs. Missing documents, errors and stale cached empty queries do not manufacture an incomplete state. Sales loading is independent, so genuine new-store setup does not wait for sales queries.

There is no separate saved onboarding-complete flag. The canonical persisted inputs remain `stores/{profile.storeCode}.benefitNumber`, the presence of `vatRegistered` (false correctly means configured but not VAT-registered), products filtered by the same `storeCode`, and cashier-role users filtered by that store. Profile saves write the same store document. No migration or new Firebase writes were introduced for this fix.

Each asynchronous load is scoped to the current authenticated UID, store code and request generation. Old account/store responses cannot overwrite newer state. Readiness is revalidated when resuming the app or returning Home after setup-related navigation. No timer, artificial delay, opacity/visibility workaround or permanent dismissal flag was added.

## Verification

- Seven focused regression tests pass: pending reads, five fully recreated widget mounts with each read released individually, genuine incomplete stores, stale cached defaults, failed/missing store reads, account changes with late responses, and correct store-code lookup.
- Full Flutter suite: **275 passed, 0 failed**. Analyzer: **no issues found**.
- Real browser tests used the actual ShopPad app shell, AuthWrapper, synchronization service, persistent browser authentication/storage, Firebase Auth Emulator and Firestore Emulator with the current local rules. No production store data was read or modified.
- The Edge browser process was completely closed and relaunched five times for a configured store. A DOM/semantics mutation monitor observed **zero checklist appearances** during every initialization.
- A genuine new store still displayed its four-step checklist after confirmed reads.
- In an additional scenario, the browser was closed while its cache still contained incomplete setup. The canonical emulator records were then completed. Two browser-process reopens showed **zero checklist appearances**, without clearing storage. A separate incomplete-start control retained the checklist.
- In total: **seven configured-store cold starts without the card**, plus **two genuine incomplete-store controls with the card**. No browser page errors occurred. A fake-key Auth restoration request that the JS SDK begins before Flutter attaches its emulator is explicitly redirected to the local Auth Emulator; production Firebase requests are blocked by the browser harness.

Reproducible widget tests are `test/reports/owner_onboarding_initialization_test.dart`; the controlled Firestore test helper is `test/support/owner_read_firestore.dart`. Browser harnesses, screenshots and demo entry point are ignored local QA artifacts in `.security-audit`; production `main.dart` and authentication code were not changed.
