# Trusted checkout server

This server replaces direct client checkout writes. It uses Firebase Admin on the **server only**. No paid product API is used. No hosting plan, billing account, live data or security rules were changed while implementing it.

## Status and activation constraint

The implementation and restrictive rules are local. **Do not publish the rules alone**: cashier checkout now requires the authenticated endpoint. The Flutter entry point uses `TrustedSaleGateway` and intentionally refuses to fall back to insecure direct writes when the endpoint is missing. The existing published preview was not updated by this change.

Firebase Hosting serves static files and does not run this Node server by itself. Supply an existing trusted Node 22+ host with HTTPS, or choose a hosting option explicitly. No paid plan should be enabled automatically. A free host must still support server credentials, outbound Firestore access, sufficient request duration and exact CORS origins.

## Server setup (requires an authorized hosting environment)

1. `npm ci --prefix server --ignore-scripts`
2. Configure `GCLOUD_PROJECT=shoppad-f3d43`, `NODE_ENV=production`, `PORT`, and `SHOPPAD_ALLOWED_ORIGINS` (comma-separated exact frontend origins, including the current preview URL).
3. Provide server-side Application Default Credentials. Prefer workload identity where supported; otherwise use a host secret store for the credential file. Never copy privileged credentials, CLI login files or service-account JSON into Flutter, Hosting assets, Git, screenshots or chat. Grant only Firestore data access and the Auth user-read permission needed for revoked/disabled-token checking. Do not use an administrative personal login as a deployed server credential.
4. Run `npm start --prefix server` behind HTTPS. The only operation is `POST /checkout`. Requires a Firebase ID token in the Authorization bearer header and JSON content.
5. Build Flutter with `--dart-define=SHOPPAD_CHECKOUT_URL=https://YOUR_AUTHORIZED_HOST/checkout`. This URL is public configuration, not a secret.
6. Verify Auth, CORS, checkout, retry, stock, VAT and owner/cashier behavior on that host. Then coordinate publishing the restrictive rules and matching app/server. Never leave an insecure client-write fallback active.

## Security behavior

- Firebase SDK verifies the token and checks revocation/disabled Auth users. The transaction independently checks current store membership, active status and actual store owner.
- Every product line is checked against authoritative store data; unit prices, stock, totals, tax and correction audit are server-derived.
- Unknown items are detected anywhere in the list. Only one standalone, owner-authorized shared-reference item is allowed; no permanent product is created.
- The receipt and stock are one atomic transaction, including carts of 100 distinct products. Stable intent digests make concurrent retries idempotent. Matching legacy confirmed receipts are not deducted again.
- Existing manual discounts remain permitted up to the subtotal, as in the original cashier interface. Owner bundle offers are validated separately. The actual receipt identifies the discount; a client cannot disguise it as a lower unit price. Changing discount permissions would be a separate product policy decision.
- Stock shortage correction remains supported because the existing checkout explicitly allows sales of physical items that exceed the recorded count. Corrections are computed and audited by the server, never copied from client-supplied audit data.
- Private cost snapshots are read from owner-only cost data for owner sales only; a cashier cannot inject private costs.
- Owner product edits, restock permissions, refunds and backups retain their existing privileges. The owner is a trusted administrator of their own store, not an adversary excluded from changing their own data.
- JSON requests are bounded to 512 KiB; origins are exact, replies are not cached, and internal SDK errors are not returned to clients. Configure host-level abuse/rate protection before public activation. CORS is not authentication.

## Local verification

Use a demo project only. Tests assert the dedicated local ports and will not run against production:

- Firestore: `127.0.0.1:9184`, project `demo-shoppad-security`.
- Authentication: `127.0.0.1:9197`.
- `node --test --test-concurrency=1 server/test/*.test.cjs`

Run within Firebase `emulators:exec` with Auth and Firestore configured. The isolated local config used for this task is `.security-audit/trusted-server-emulator.json`. The separate Firestore client-denial suite remains `test/security/firestore_rules.test.cjs` (set its emulator port explicitly).

## Remaining boundaries

This prevents the two reproduced client-write bypasses after coordinated activation. It does not prove cash or bank payment actually occurred, make a malicious device trustworthy, provide end-to-end encryption, encrypt existing IndexedDB/Sembast queues, or guarantee there are no undiscovered flaws. Device encryption needs a key/unlock/recovery policy and a tested migration that never loses pending receipts. App Check and host-level rate controls require deployment configuration; neither replaces the financial checks above.
