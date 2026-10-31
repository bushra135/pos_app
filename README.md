# ShopPad

ShopPad is a Flutter point-of-sale app. A cashier scans a product barcode with the phone camera, reviews the cart, confirms payment, and shares a receipt. Owners manage products, cashiers, reports, payment settings and recovery copies.

For a guided code walkthrough and discussion preparation, read [Code discussion guide](docs/CODE_GUIDE.md). Security controls and remaining limitations are documented in [Security status](docs/security/SECURITY.md).

## Run and verify

Use Flutter with Dart 3.11 or newer, matching `pubspec.yaml`.

```sh
flutter pub get
flutter run
```

Use a real camera-capable device to verify scanning, permissions, vibration, PDF sharing and printing. Firebase access and the appropriate server rules are required for sign-in and server data. The existing project configuration is in `firebase_options.dart` and `firebase.json`.

```sh
dart format lib test
flutter analyze
flutter test
```

Windows desktop plugin builds may require Windows Developer Mode for symlink support. Printing uses the operating system print service; direct Bluetooth ESC/POS thermal printing is not implemented.

## Folder responsibilities

| Folder | Purpose |
| --- | --- |
| `lib/app` | Shared theme, colors, spacing and typography |
| `lib/models` | Cart items, saved sale snapshots and shared report interpretation |
| `lib/screens` | Pages grouped by feature: authentication, scanning, checkout, products, reports, profile and backup |
| `lib/services` | Firebase operations, sales synchronization, local storage, PDF generation and recovery |
| `lib/utils` | Small reusable helpers: cart operations, barcode duplicate guard and image preparation |
| `lib/widgets` | Reusable views: product images, receipt display and synchronization status |
| `test` | Automated checks grouped by feature, with shared fakes in `test/support` |
| `docs` | Code walkthrough, backup notes and the security status |

Generated platform folders (`android`, `ios`, `web`, `linux`, `macos`) and `firebase_options.dart` are integration code. Do not memorize or manually rewrite generated registration files. `.dart_tool` and `build` contain tooling output, not the application's business logic.

## Follow one sale through the code

1. `main.dart` initializes Firebase, persistent local storage and `SaleSyncService`.
2. `auth/auth_wrapper.dart` checks the session, email verification and store role.
3. `scan/scan_screen.dart` reads the camera barcode or manual input. `BarcodeScanGuard` prevents a continuously detected label from repeatedly adding units.
4. `SaleSyncService.findProduct` finds the store product and checks available stock, including pending reservations and the cart.
5. `CartManager` adds or updates the in-memory cart. The scan screen displays the same cart used by `cart/cart_screen.dart`.
6. `checkout/checkout_receipt_screen.dart` creates a fixed `SaleRecord` and submits it through `SaleSyncService`.
7. `LocalPosStore` durably keeps pending cash receipts. `FirestoreSaleGateway` checks authoritative stock and saves the sale with stock changes in a Firestore transaction. A stable sale ID prevents repeated submission from making another sale.
8. `SaleReceiptView` displays the saved snapshot after the cart is cleared. `ReceiptService.generatePdf` produces the PDF. Export errors do not resubmit payment.

The scan screen's `build` method lists its six UI sections. Each section has a named builder; camera and cart logic stay in named event handlers in the same file.

## Important files for the project discussion

| File or class | Question it answers |
| --- | --- |
| `screens/scan/scan_screen.dart` | How does the phone scan and display the live cart? |
| `utils/barcode_scan_guard.dart` | Why does a held barcode not add units every camera frame? |
| `utils/cart_manager.dart` and `models/cart_item.dart` | How are quantities and cart totals calculated? |
| `models/sale_record.dart` | What is saved, and why is a receipt a fixed snapshot? |
| `services/sale_sync_service.dart` | What happens when a sale is submitted without a connection? |
| `services/sale_gateway.dart` | How are stock changes and duplicate sale IDs checked online? |
| `services/local_pos_store.dart` | How are pending sales and stock reservations kept after a restart? |
| `services/receipt_service.dart` | How is a PDF made from the saved sale? |
| `services/backup_service.dart` | How do recovery copies avoid overwriting newer records? |
| `screens/ai/ai_assistant_screen.dart` | How are local store insights calculated? |

The native and web database files are intentionally separate. Conditional imports select a device file database or browser IndexedDB; all callers use `local_pos_database.dart`.

## Data and current limitations

- Firestore collections are `users`, `stores`, `products` and `sales`. Store operations must be scoped by `storeCode` and protected by server rules. Hiding an owner-only button is not authorization.
- The cart is held in memory and does not survive app restarts. Pending accepted cash sales are durable and separate from the cart.
- Cash is supported. BenefitPay uses store-provided payment details and manual receipt confirmation; there is no bank payment-verification integration.
- The assistant calculates insights locally using English keyword rules and store records. No AI API key or paid model is required. It still loads records from the existing Firebase store.
- Reports read saved store data. Current checkout does not implement actual tax/discount calculations, returns or spreadsheet import.
- Barcode input identifies a product already registered for the store; it does not automatically obtain the store's selling price.
- Low-stock information is displayed in product management. Validate real-device scanning performance before claiming equivalence to a dedicated scanner.
- Backup is manual cloud recovery, not iCloud or a full database rollback. Read [Backup & recovery](docs/BACKUP.md) before use; owner-only server rules are deployed; recovery should still be rehearsed with test data before relying on it.
- Cashier invitations use separate `users` records with an empty `uid`; new registered cashiers need owner approval. Availability (`onDuty`) is separate from owner-controlled account access.
- Email verification uses Firebase Authentication verification links. Users open the emailed link, then return to confirm verification; no external email provider or Cloud Functions deployment is required. Delivery to the inbox rather than spam is not guaranteed.

## Product images and compatibility

`ProductImageData` converts a selected image to a PNG with maximum dimension 640 pixels, reducing it further until the raw output is at most 180 KiB. Originals over 20 MiB are rejected. Images are stored in `products.image` as a Base64 data URL, without Firebase Storage. Existing image URLs are also supported.

Image preparation, barcode checks and product writes use 20-second timeouts. A delayed Firestore write can still complete; retrying in the same product dialog reuses the document ID. Embedded image data is excluded from sale lines to keep receipts below Firestore document size limits.

Legacy `stock`/`quantity` and `minStock`/`minQuantity` fields remain supported. Do not rename persisted fields, local database names or sale identifiers as part of cosmetic cleanup.

The bundled Cairo font and license are in `assets/fonts`. The `image` package is pinned in `pubspec.yaml` to avoid the archive API incompatibility encountered in PDF dependency resolution. Keep `pubspec.lock` when changing dependencies.

## Code conventions

- English identifiers and comments; `UpperCamelCase` classes, `lowerCamelCase` members and `snake_case.dart` files.
- Private widget-state fields start with `_`; boolean names describe a condition, such as `_isAddingProduct`.
- Name methods by the operation: `_addProductByBarcode`, `_undoLastAddition`, `listBackups`, `createBackup`, `restoreMissingRecords`, `generatePdf`.
- Separate Dart SDK, package and project imports. Let `dart format` handle layout.
- Comments explain decisions and invariants, especially payment persistence, stock checks and retry behavior. Avoid comments that only repeat the next line.
- Keep UI builders in the screen unless a view is reused or has a separate responsibility. Avoid creating a file for every small widget or combining unrelated features to reduce file count.


## Fast camera lookup

Camera checkout uses `findProduct(preferCache: true)` to read the locally synchronized catalogue first. Cache misses fall back to a server lookup when online. Cached names, prices and stock can lag behind another device until the product stream updates; stock is checked again on submission. The camera detection interval is 100 ms, not an unrestricted frame loop. Up to 12 subsequent camera detections are processed in order while product lookup is busy; full queues accept no further scans until capacity is available. Each successful addition has its own feedback. The existing duplicate guard remains active. These settings reduce software waiting, but do not constitute a measured camera scan latency or a guarantee of outperforming a dedicated scanner.

## Free barcode product information

`BarcodeCatalogService` reads the public Open Facts API v3 with `product_type=all`, allowing official redirects across Open Food Facts, Open Products Facts, Open Beauty Facts and Open Pet Food Facts; there is no API key or paid AI dependency. In Products > Add Product, scanning a barcode automatically looks up available product details. The lookup button also works for a typed barcode. Only empty name, category and image fields are filled. The owner reviews the suggestion and supplies the store selling price and stock before saving. Existing user details are preserved. A missing product during online checkout opens a preview, not a sale or an automatically stocked product; offline cache misses and stock errors do not trigger external lookup.

Coverage is community supplied, including general products, beauty and pet food as well as packaged food; many manufacturer and local products are still absent. Decoding a barcode is distinct from finding a matching catalogue record. Lookup needs internet. No store, customer, price or payment data is submitted to the provider. Supported numeric barcode lengths are 8, 12, 13 and 14, with leading zeros preserved. Other internal barcodes remain valid for manual product entry. Responses are cached in memory for one hour (five minutes for no match), simultaneous identical requests share one call, reads are limited to 15 per minute per app instance, and requests time out after four seconds; the form also has a Stop lookup action that ignores late results. Provider failures keep manual entry available. This per-instance limit cannot coordinate several devices sharing a public IP.

Imported records retain `catalogueSource`, with source URL and licence labels, shown in the product form and checkout preview. Data is from the relevant Open Facts catalogue contributors under ODbL/DbCL; images retain their CC BY-SA terms. Before publicly redistributing an adapted catalogue, follow the provider's attribution and share-alike requirements. Store prices and quantities are supplied by the owner, not by the provider. No data is uploaded back to Open Food Facts. Replace the prototype User-Agent description with the project's public contact information before public rollout and complete the provider's API usage form.

- API: https://openfoodfacts.github.io/documentation/docs/Product-Opener/v3/products/get-api-v3-product-code/
- Usage and rate limits: https://openfoodfacts.github.io/openfoodfacts-server/api/
- Attribution and licences: https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/license-be-on-the-legal-side/

A live read of the documented example barcode `3017620422003` returned Nutella and a front-image URL during development. This does not establish coverage of Bahrain products or verify camera performance on a physical device.

A second live all-category lookup of `6111259733749` resolved a general cleaning product with `product_type=product` and an Open Products Facts image URL. General catalogue coverage remains incomplete; no claim is made that every stationery or manufacturer barcode has metadata.



### Browser camera compatibility

On web, the product scanner and cashier camera use the bundled ZXing decoder in a browser-owned inline video view. The cashier camera opens automatically inside the Scan page, with the live cart and navigation remaining visible. Camera startup errors provide an inline retry control. Cashiers scan continuously, see the cart total, and choose Review sale to return to the cart. A visible barcode stays latched until absent for 1.6 seconds; Add same item explicitly adds another unit. Unknown products close the camera and open the existing product information dialog. Closing a view stops its camera tracks. Native mobile scanning still uses mobile_scanner.

Product names can suggest a category using local English and Arabic keyword rules. Unknown/ambiguous names stay blank and manually edited categories are preserved. Photo recognition was cancelled and its model/runtime files were removed; ordinary photo uploads remain available.

### Physical stock corrections at checkout

New checkout receipts opt into physical stock correction. If five physical units are sold while recorded stock is three, all five units are charged, a +2 correction is recorded in the sale's stockCorrections/stockCorrectionUnits fields, and stock ends at zero. The product also references its lastStockCorrection. Correction and sale/stock writes happen in one Firestore transaction. Replaying the receipt ID does not apply the correction twice. Legacy pending receipts keep their original policy. Invalid, missing and other-store product data still reject the sale.

A saved checkout receipt replaces the loading state immediately. Audio and pending-sync notices do not block receipt display. A late successful server acknowledgement removes the same local pending receipt, and the receipt status refreshes. No second sale is generated when retrying synchronization.

### Owner sales history and cashier performance

Owners open Reports > Sales history for receipts and Home > Top cashiers for the separate performance page. History is store-scoped and defaults to all time, with receipt/cashier/product search, cashier and period filters, live sale updates, receipt lines, payment details and stock correction audit. Compatible completed receipts reuse the PDF/share/print view and return to the preserved history screen. Device-only pending receipts become visible after synchronization.

Top cashiers ranks completed non-refund receipts by sales value after refunds recorded on the sale, then receipt count, for the selected period. Owner sales, incomplete/cancelled records and receipts without a cashier UID are excluded from ranking; those receipts remain visible in history. Cashiers group by authenticated UID so identical names do not merge; exact ties share the top designation. History checks the active user's owner role and store before querying; production Firestore rules remain authoritative.


### Filtered owner exports

History supports inclusive custom local date ranges, cashier, payment method, product, receipt status, stock-correction-only and text search together. Clear report filters resets all selections. The displayed net receipt total excludes incomplete receipts and subtracts refund transactions. Selecting a product also shows its sold units and line value before receipt-level discounts/tax; the separate receipt total includes the entire matching receipt. Cashier ranking uses the date period, independently of history-specific filters.

The web version exports exactly the filtered receipts as UTF-8 CSV with a BOM for Arabic Excel text. This is CSV, not an XLSX workbook. Amounts retain three BD decimal places, text is quoted and formula-like text is escaped. Download is local through a browser Blob URL, without an external service. Native CSV download is currently unavailable; filters and receipt PDF features remain available. Device-only pending receipts must synchronize before appearing in owner history or exports.

Sales history and Top cashiers are independent routes with separate period/filter state. Tapping a cashier opens a new history route filtered to that cashier and date period; Back returns to the performance page. No combined tabs are shown.


## Project structure

```text
lib/             Application source grouped by responsibility and feature
assets/          Fonts, logo and audio used by the app
web/             Web entrypoint, browser camera and bundled decoder
android/, ios/   Mobile platform projects
linux/, macos/   Desktop platform projects
test/           Tests grouped into assistant, backup, catalog, checkout,
                 reports, scanning, web and shared support
docs/           Code guide, backup notes and security status
```

Run commands from the project root. Flutter discovers all nested Dart tests with `flutter test --no-pub`. Browser tests run with:

```sh
node --test test/scanning/browser_scanner.test.cjs test/reports/report_export.test.cjs test/web/web_bootstrap.test.cjs
```

The unused numeric-code Functions backend and its Flutter client dependency were removed. Email verification continues to use Firebase Auth links. `.dart_tool`, `build` and `.firebase` are generated caches/output, not application code. Native platform projects remain available for building the app on their platforms.

Server access rules are in `firestore.rules`. Changes require emulator authorization tests and `firebase deploy --only firestore:rules --project shoppad-f3d43`. New owner registration writes its profile and store atomically; cashiers cannot join an existing store with active permissions just by knowing its code.


## Phone preview links

The current test channel is `scan-direct`. Deploy updates to this same channel rather than creating a new URL for each fix. Query parameters such as `?release=...` do not create another channel.

Preview URLs are public: anyone with the URL can load the sign-in page and downloaded frontend. Store data still requires authentication and Firestore authorization. Firebase project members with suitable Hosting permissions can inspect channels and retained release history; an ordinary visitor does not receive that management history from the app.

Do not remove an old channel or clear its browser storage until any device-only receipts saved on that origin have synchronized. Preview links expire and are for testing; Hosting storage and transfer quotas still apply. See https://firebase.google.com/docs/hosting/test-preview-deploy and https://firebase.google.com/docs/hosting/manage-hosting-resources.


### Sync status placement

Profile > Sales sync always opens saved cash receipts and connection details. The top banner is hidden when online with no pending receipts, sync activity or error; offline and pending/conflict states remain visible. Profile shows the account role once under the name. Saved cash amounts use BD with three decimal places.


### Owner cashier mode

Owners switch from Home or Profile to the cashier workspace and back using the same authenticated account. This changes UI mode only; no role/store/approval fields are rewritten and ordinary cashiers have no owner-mode action. The cart and saved pending receipts remain under the same user/store. Owner sales are recorded with the owner UID and appear in store history; employee cashier rankings continue to exclude owners. Returning to management refreshes the dashboard.
