# Dashboard/profile navigation loading — 27 November 2026

## Traced causes
- Owner and cashier shells rendered just the selected destination inside an AnimatedSwitcher. Leaving Profile or Dashboard disposed the page; returning reran its entire initialization and reset local view state.
- Profile loading serialized the profile read, Firebase Auth reload/optional email update, and store read before showing the UI.
- Dashboard/home reads that only depend on the authenticated store were serialized.
- ProfileAvatar decoded base64 into a new byte array on every build, causing a different MemoryImage cache identity even when the photo was unchanged.

## Changes
- A small lazy RetainedTabBody preserves only visited Dashboard/Profile destinations. It never creates unvisited tabs, pauses hidden tickers, excludes hidden keyboard focus, and disposes non-retained camera/cart destinations on departure. There is no timer or arbitrary loading delay.
- Owner retention is keyed by the complete UID/store/Firestore tuple; cashier retention uses the equivalent tuple. Account/store/backend changes discard retained state. No global or persistent private-data cache was introduced.
- Re-entering retained reports/profile refreshes in place without replacing loaded content with a blocking loader. Last displayed data remains visible during refresh and is replaced by the result; it is not claimed to be a fresh server snapshot before the request finishes.
- Profile Auth/email confirmation refresh runs after the initial UI data is available, with UID guards and in-flight deduplication. Email-token/Firestore ownership verification remains intact.
- Profile/report late responses use generation and UID checks and cannot apply to a disposed page or another account. Payment-number refresh does not overwrite an unsaved edit.
- Owner home store/cashier/product queries run concurrently; the existing server-confirmed onboarding readiness checks remain. Report sales/product queries also run concurrently. Sales filtering, permission checks, offline behavior and owner-only costs are preserved.
- Profile image bytes are reused until the image changes or is removed, retaining image-cache identity across tab rebuilds.

## Verification
- Full Flutter suite: 295 passed before the final avatar-cache change and final extra integration test.
- Latest focused suite: 11 passed, including original photo processing/save tests, unchanged-image cache identity, replacement/removal, lazy mounting/disposal, account/store cache clearing, late-response/dispose guards, concurrent report reads, in-place refresh, and actual OwnerHome Dashboard state preservation during tab navigation.
- Earlier targeted owner/cashier/onboarding/Arabic regression suite: 26 passed.
- No physical phone/network latency benchmark was performed; no percentage speedup is claimed. Request concurrency and preserved page state were verified with gated asynchronous reads.
- Changes remain local. The pending trusted checkout migration still requires its authorized backend/HTTPS endpoint before a matching complete app release can be activated. No hosting, rules, billing or live data changes were made for this task.

- Final analysis: no issues. Isolated release web build succeeded (`.security-audit/navigation-web-build`), with the existing Cupertino font warning. It was not deployed.
- Final scope-key integration rerun: 5 passed after switching to collision-free UID/store/Firestore tuple keys.
