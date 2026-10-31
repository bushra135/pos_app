# ShopPad code discussion guide

## Start here

Read these files in this order. Do not start by memorizing widget layouts.

1. `lib/main.dart`: initializes Firebase and the sale synchronization service, then starts `ShopPadApp`.
2. `lib/screens/auth/auth_wrapper.dart`: chooses the verified user's owner or cashier home.
3. `lib/screens/scan/scan_screen.dart`: receives a barcode, finds the store product and updates the cart.
4. `lib/utils/cart_manager.dart`: holds the shared in-memory cart and calculates quantities/totals.
5. `lib/screens/checkout/checkout_receipt_screen.dart`: takes a fixed cart snapshot and submits payment.
6. `lib/services/sale_sync_service.dart`: saves accepted cash sales locally and coordinates synchronization.
7. `lib/services/sale_gateway.dart`: validates and commits the sale and stock changes in one transaction.
8. `lib/widgets/sale_receipt_view.dart`: shows the saved receipt; `receipt_service.dart` builds its PDF.

## Folder map

| Folder | Responsibility |
| --- | --- |
| `lib/app` | Shared colors, typography, spacing and theme |
| `lib/models` | Data structures, fixed sale snapshots and read-only report interpretation |
| `lib/screens` | Feature pages and their event handlers |
| `lib/services` | Storage, Firebase operations, synchronization, catalog lookup and exports |
| `lib/utils` | Small reusable calculations and input helpers |
| `lib/widgets` | Reusable visual components |
| `web` | Browser startup, camera integration and local file download |
| `test` | Behavioral regression checks grouped by feature |
| `docs` | Discussion guide, backup and security notes |

## How to read a screen

- Constructor arguments are dependencies or initial values; optional injected dependencies make tests possible.
- Fields beginning with `_` are private to that Dart library.
- `initState` loads initial data or starts listeners once.
- Event handlers perform actions such as scan, save, filter or export.
- `build` and `_build...` methods describe the interface.
- `dispose` stops listeners, timers and controllers when leaving the screen.
- A `mounted` check prevents updating a widget after it has been removed.
- English section comments mark responsibilities in the larger screens.

## Main features

| Feature | Main entry | Supporting logic |
| --- | --- | --- |
| Owner home | `screens/owner/owner_home_screen.dart` | Dashboard and Top cashiers entry |
| Products | `screens/products/products_screen.dart` | Catalog service, image helper and category suggestion |
| Scan and manual input | `screens/scan/scan_screen.dart` | Barcode guard, browser scanner and cart manager |
| Payment | `screens/checkout/checkout_receipt_screen.dart` | SaleRecord, synchronization and gateway |
| Report dashboard | `screens/reports/reports_screen.dart` | Shared ReportSale parsing |
| Receipt history / cashier ranking | `screens/reports/sales_history_screen.dart` | Separate routes, owner/store checks, filters and CSV |
| Local assistant | `screens/ai/ai_assistant_screen.dart` | Keyword routing and shared ReportSale parsing |
| Recovery copies | `screens/backup/backup_screen.dart` | Backup service; see BACKUP.md |

`ReportSale` reads current and legacy records for the report dashboard and local assistant. Its number, date, item-key and payment helpers are defined once in `models/report_sale.dart`. `SaleRecord` has a different job: it is the immutable checkout snapshot used for receipts and retrying queued sales. History has its own adapter because it must also show incomplete receipts and audit fields.

## Explain one sale

Camera or manual barcode -> store product lookup -> CartManager -> SaleRecord -> local pending queue -> Firestore transaction -> saved receipt.

- The camera can see the same barcode in many frames. The duplicate guard prevents repeated additions while the label stays visible.
- The cart is temporary memory. Accepted pending cash sales use durable local storage.
- The receipt ID stays the same on retries. A server acknowledgement lost in transit must not create a second sale.
- The Firestore gateway reads authoritative product records before writing sale and stock changes atomically.
- If physical stock sold exceeds recorded stock, an opted-in sale records the shortage correction and ends stock at zero. Old pending receipts retain their original policy.
- PDF sharing uses the saved receipt snapshot and never submits another payment.

## Reports and local assistant

The report dashboard and assistant share financial parsing to avoid maintaining duplicate formulas. Both support legacy field aliases in the same priority order. The assistant uses local keyword rules and calculations; it does not call a paid language model.

Receipt history combines date, cashier, product, payment, status and stock-correction filters. Its CSV export uses the same filtered rows as the screen. Product line values are before receipt-level discounts/tax; receipt totals include all items on a matching receipt.

Top cashiers opens from the cashier summary card on the owner home. It ranks completed cashier receipts using integer fils, with exact ties shown jointly. Owner sales and records without a cashier ID do not compete. Server access rules, not hidden buttons, protect store data.

## Browser-specific code

- `web/browser_scanner.js`: browser-owned video and decoding for the mobile web camera.
- `services/browser_scanner.dart`: conditional interface selecting web or native behavior.
- `web/flutter_bootstrap.js`: versioned app entrypoint to avoid loading an older cached bundle.
- `web/report_export.js`: downloads CSV on the user's device without uploading the report.
- Conditional database implementations select IndexedDB on web and a device database on native platforms.

## What to review before the discussion

Run `flutter analyze --no-pub`, `flutter test --no-pub` and the Node test command in the root README. Test the camera on a real device separately. Automated tests do not establish camera quality or payment-provider integration.

Focus on why responsibilities are separated, how data flows, why transactions and stable IDs matter, and what happens offline. Generated platform registrations, `firebase_options.dart`, `.dart_tool` and `build` are integration/tool output rather than business logic.

## Refactoring rules

Keep database field names and receipt formats compatible. Keep platform-specific integrations separate. Extract a helper when multiple callers need the same rule; keep small feature-only widgets close to their screen. Comments should explain intent and safeguards rather than narrate each line.
