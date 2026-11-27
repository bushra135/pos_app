# Product and profile photo fixes — 26 November 2026

## Causes and changes
- Name-only shared catalogue entries previously stopped lookup before public photo lookup. Owner Find Product now enriches these records from the existing free sources, preserving shared names/prices and owner edits. Failed enrichment keeps existing information. Requests are deduplicated and negatively cached.
- Profile updates previously excluded `photo` from the Firestore whitelist. Own-profile JPEG data URLs are now permitted, bounded to 120,000 characters; other-account photo changes and role/store changes remain prohibited. Saving has a 20-second timeout.
- Hosted product creation required atomic barcode-claim rules that had remained local under the earlier deployment restriction. After explicit user approval, the complete tested rules were released to shoppad-f3d43 on 26 November 2026. No live records were edited.
- Product editor shows barcode, name, selling price and stock as primary text fields. Additional fields remain editable in an optional section; photo controls remain visible. Empty category saves as Other. No price is invented.
- Expansion uses ValueKey rather than PageStorageKey to avoid a boolean expansion-state collision with descendant text scroll offsets.

## Verification
- Complete Flutter suite: 279 passed, 0 failed.
- flutter analyze: no issues.
- Firestore emulator security suite: 35 passed, 0 failed, isolated demo-shoppad-security project.
- Regression coverage includes photo decoding/form fill/save, preserving edits and shared prices, missing-photo enrichment, source failure, existing photos, and optional form fields.
- Semgrep: 88 Dart files, 3 WARNING findings (two public Firebase client configuration keys and one existing profile error-code logging heuristic), no ERROR findings. Findings retained.
- git diff --check passed.

## Limits
Public catalogues cannot provide a photograph that they do not have. No specific failing customer barcode was supplied. Physical-phone image-picker and saving to a real user account were not exercised; save permission behavior was verified on Firebase Emulator. Preview build/deployment status is recorded separately in the task output. No production Hosting deployment or Git push.

## Release
Release web build completed successfully. Existing dependencies report optional WebAssembly compatibility and Cupertino font warnings; JavaScript web build succeeded. Updated only the existing phone-test Hosting preview channel. Firestore rules deployment succeeded after explicit user authorization.
