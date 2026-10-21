# ShopPad

ShopPad is a Flutter point-of-sale app. A cashier scans a product barcode with the phone camera, reviews the cart, confirms payment, and shares a receipt. Owners manage products, cashiers, reports, payment settings and recovery copies.

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
| `lib/models` | Cart items and saved sale data |
| `lib/screens` | Pages grouped by feature: authentication, scanning, checkout, products, reports, profile and backup |
| `lib/services` | Firebase operations, sales synchronization, local storage, PDF generation and recovery |
| `lib/utils` | Small reusable helpers: cart operations, barcode duplicate guard and image preparation |
| `lib/widgets` | Reusable views: product images, receipt display and synchronization status |
| `test` | Automated checks for storage, sale safety, cart layout, scanning, receipts and recovery |
| `functions` | Server-side email verification and validation; see its README for setup |

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
| `screens/ai/ai_assistant_screen.dart` | How are store questions answered using local rules? |

The native and web database files are intentionally separate. Conditional imports select a device file database or browser IndexedDB; all callers use `local_pos_database.dart`.

## Data and current limitations

- Firestore collections are `users`, `stores`, `products` and `sales`. Store operations must be scoped by `storeCode` and protected by server rules. Hiding an owner-only button is not authorization.
- The cart is held in memory and does not survive app restarts. Pending accepted cash sales are durable and separate from the cart.
- Cash is supported. BenefitPay uses store-provided payment details and manual receipt confirmation; there is no bank payment-verification integration.
- The assistant uses local data rules, not a remote language model. It should not be described as an integrated external AI service.
- Reports read saved store data. Current checkout does not implement actual tax/discount calculations, returns or spreadsheet import.
- Barcode input identifies a product already registered for the store; it does not automatically obtain the store's selling price.
- Low-stock information is displayed in product management. Validate real-device scanning performance before claiming equivalence to a dedicated scanner.
- Backup is manual cloud recovery, not iCloud or a full database rollback. Read `BACKUP.md` before use; production rule integration and real-environment checks remain necessary.
- Cashier invitations currently use separate `users` records with an empty `uid`; registration does not automatically merge the invitation.
- The six-digit email verification server service requires setup/deployment documented in `functions/README.md`.

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
