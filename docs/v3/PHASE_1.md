# Phase 1 — grocery and item intelligence candidate

## Deployment boundary

Production rules have NOT been deployed or overwritten. Deployed-rule comparison
remains unresolved. The standard APK deliberately has V3_ITEMS_ENABLED=false;
the grocery entry explains the security gate and does not subscribe to or write
new module collections. Existing accounts, groups, expenses and OCR continue.
For isolated emulator testing, or only after a verified secure rules rollout:
`flutter build apk --debug --dart-define=V3_ITEMS_ENABLED=true`.
Never use permissive production rules to enable the screen.

## Implemented features 1–7

1. Group library: deterministic normalized-name IDs, explicit Greek/English
   aliases, rename/category changes, reviewed merges, alias disable/reactivation,
   immutable correction history and undo. No fuzzy translation or stripping
   package sizes. Purchase reclassification is an audited overlay, not a rewrite.
2. Regular items: unique purchase-event IDs, receipt frequency, retailer, last
   purchase, expenditure, known quantities, weighted/latest unit prices. Backfill
   is explicit, paginated, resumable and creates only missing events. Retried
   saves/indexing cannot double-count. Grocery inclusion and quantity corrections
   are audited, revision-checked overlays; financial originals are immutable.
3. Shared shopping: realtime quantities, checked state, assignment and notes;
   one-click regular-item suggestions; transactional operation IDs prevent retry
   double additions. Checking an item never pays an expense or changes stock.
4. Kitchen: per-receipt reviewed restock, optional expiry, low-stock display and
   shopping suggestion; immutable restock/consumption events, manual consumption,
   no inferred use, no negative stock and no event replay. Expiry is informational.
5. Prices: same item and comparable canonical units only, dated retailer history,
   weighted/latest price and movement. Missing legacy quantity is explicitly
   unknown and excluded from comparisons until reviewed. Quantities use integer
   thousandths; financial amounts remain integer cents.
6. Duplicate warnings: on-device normalized-image hash plus merchant/date/total/
   item signature, group-restricted metadata, explicit user override. Same store
   and amount alone are not proof; no receipt is automatically dropped.
7. Greek/English OCR: retains bundled ell+eng, EXIF correction, preprocessing,
   dual passes, uncertainty warnings, explicit quantity/unit suggestions and
   mandatory review. Images remain local. Only reviewed fields and fingerprints
   sync; raw OCR text and receipt image bytes do not.

## Data and migration

All new data lives under households/{groupId}. Existing user/household/expense/item
paths and documents stay unchanged. New collections: catalog, catalogChanges,
itemAliases, aliasChanges, purchases, purchaseCorrections, purchaseChanges,
shopping, shoppingEvents, stock, stockEvents and receiptSignatures. Every path
requires active membership; audit records are immutable and mutations validate
revision, actor, timestamp and paired evidence. Cross-group references are not
allowed. Existing source expenses remain append-only in this phase; financial
correction/refund/settlement work belongs to Phase 2.

When enabled, a successful reviewed save indexes its existing source item lines.
If indexing fails after expense acknowledgement, retrying the same expense ID
recognizes the committed expense and resumes indexing. Explicit historical import
never assumes quantities from names or invents missing item breakdowns. Imported
records with missing quantities use an explicitly unverified placeholder; they
cannot contribute unit prices until reviewed. No backfill runs on app startup.

Rollback disables V3_ITEMS_ENABLED and keeps additive collections and compatible
rules. Do not delete original or derived records to roll back. Never roll rules
back to a permissive version. Review/testing on actual Android/iOS devices and
real Cyprus receipts is still needed; Linux does not establish iOS compilation.

Verification for this candidate: analyze clean; 60 Flutter tests, 25 real
Firestore emulator tests, and the standard Android debug APK build passed.
The APK uses version 3.0.0-phase.1+5 and the existing signing identity.
