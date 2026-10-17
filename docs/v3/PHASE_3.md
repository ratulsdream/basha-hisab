# Phase 3 — convenience candidate

The owner requested implementation to continue with production rules/data untouched.
The Phase 0 deployed-rule comparison is still a rollout blocker. Standard APKs
leave V3_ENABLED false. Enable only against an isolated emulator or after an
owner-reviewed secure rules deployment. No workflow deploys Firebase rules or Functions.

## Features 15–18

- Per-account, owner-only notification preferences, all off initially; permission
  requests occur only after explicit opt-in. Foreground shared expense/shopping
  updates, stock threshold crossings, budget thresholds, recurring review and
  monthly settlement reminders. Initial snapshots do not replay old expenses.
  Reminders use an explicit IANA timezone, inexact Android scheduling and a
  bounded queue under iOS limits. Stop/cancel on sign-out and group removal.
- Optional data-only FCM receiver and undeployed Functions source in `functions/`.
  Both recipient preferences and current membership are checked. Tokens are
  owner-only; delivery claims have no client access. Payloads contain identifiers,
  never receipt/merchant/amount/private expense text. Dedupe is best effort and
  at-most-once server attempts favour quiet failure after uncertain delivery.
  Notifications are advisory; Firestore remains authoritative.
- Monthly PDF and real OOXML `.xlsx` exports with shared expenses/items,
  categories, dates, payers, group/currency, repayments/reversal references and
  exact settlement. Bundled DejaVu font supports Greek without network downloads.
  Spreadsheet strings cannot execute formulas. Private expenses/items require
  an explicit checkbox and are separate sheets/sections. Exports label cached
  data and generation time. Share files only after checking their contents.
- SQLite WAL/FULL durable outbox, partitioned by authenticated account, original
  group and stable expense ID. Reviewed structured data only; no receipt images.
  Restart resets interrupted sends to pending. A successful server transaction
  (including deterministic derived indexing/signature recovery) is required
  before removing a draft. Ack-loss retries reuse the ID; changed payloads reject.
  Pending/needs-review UI, retries, local draft export/discard and explicit
  duplicate override. Permission errors or stale membership require review;
  drafts are never silently moved to a different group or user. A local discard
  never deletes an expense that may already have been server accepted.
- Permanent profile details, safe account binding, existing group invitations,
  switching, locally remembered selection and partial-signup recovery retained.
  Auth valid sessions show the shell before asynchronous profile/group loading.

## Migration and rollback before installing

1. Keep the existing Firebase project and native configuration/bundle IDs. Do not
   uninstall/clear app data if unsynced v2 drafts exist. Install over the existing
   compatible debug-signed app; signing-key mismatch needs the original key.
2. Review the deployed rules export when available with
   `python tool/security/audit_rules.py --help`. Compare it with this repository,
   run emulator tests, review indexes and back up production before any separately
   authorized rules deployment. This work has not performed that deployment.
3. Legacy membership migration is additive and idempotent on account recovery.
   Existing users/households/expenses/items stay in place. New metadata defaults
   to shared/equal/uncategorized; no automatic bulk rewrite or deletion.
4. Grocery indexing/backfill is explicit and repeatable; it does not edit original
   receipt rows. Recurring templates create nothing until reviewed confirmation.
   Private data is written only in the owner's namespace.
5. After verification, test a build with `--dart-define=V3_ENABLED=true` against
   isolated test data before production enablement. V3_REMOTE_NOTIFICATIONS stays
   false until the server/APNs steps below are completed.
6. Roll back by disabling entry to affected new modules while preserving all data.
   After real custom splits, refunds, private spending or repayment records exist,
   an old v2 client cannot correctly represent v3 finances; do not treat an old
   APK as a financial rollback. Fix forward using the preserved source records.

## Manual configuration / blockers

- Production rules comparison: no administrative Firebase connection/export is
  available. Existing app config files cannot read deployed rules. No need to
  copy long rules from Android to continue repository tests.
- Optional Functions: review `functions/index.cjs`, install pinned dependencies,
  configure an appropriate region, billing and `BASHAHISAB_NOTIFICATIONS_ENABLED=true`
  only after owner approval. Functions are not referenced in firebase.json and
  cannot be accidentally deployed by the supplied app workflows. Default is off;
  no paid cloud OCR, Storage, scheduler or server service is required for scans.
- iPhone remote delivery requires Apple Developer/APNs key or certificate,
  Firebase APNs upload, matching `Com.bashahisab.app`, Push Notifications capability,
  signed aps-environment entitlement and a physical device. Background mode is
  in the source. Linux cannot validate signing/building iOS. Background silent
  pushes are best effort and subject to OS delivery restrictions.
- Physical Android/iPhone permission, notification scheduling after reboot,
  force-stop/relaunch, camera/OCR and Excel-app opening remain device acceptance
  checks. Automated tests exercise actual on-disk SQLite close/reopen and lost
  acknowledgement, not a claim of a physical phone restart test.

## Reproducible validation

`flutter analyze`, `flutter test`, `node --test functions/notifications.test.cjs`,
Firestore emulator rules tests (`tool/rules-tests`), actionlint and Android debug
build. Linux SQLite tests require libsqlite3-dev (installed in CI).

Device acceptance: enable v3 only on a verified test project; enable airplane
mode, review/save two receipts, confirm Pending drafts shows unconfirmed state;
force-stop and reopen (do not clear storage), confirm both IDs/data remain; change
membership from a second test device; reconnect and check stale draft pauses;
retry an unchanged draft twice and verify exactly one expense with immutable
items. Sign out/in as another account and verify no prior account drafts appear.

## Phase validation record

79 Flutter unit/widget tests, 31 official Firestore emulator authorization tests,
2 notification policy tests and 3 rule-audit tests passed. Flutter analyze and
actionlint passed. Android universal debug APK 3.0.0-phase.3+7 built and signature
verified. Exact APK/source hashes are recorded by the delivery workflow manifest.
Optional Functions dependencies are locked and handlers load locally, without a
server deployment. iOS and physical-device acceptance are not claimed.
