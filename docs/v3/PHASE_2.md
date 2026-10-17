# Phase 2 — planning and settlement candidate

No production rules or documents have been deployed/altered during development.
The owner explicitly requested continued implementation despite the pending
comparison with deployed rules. All v3 modules remain gated by V3_ENABLED (or the
compatible V3_ITEMS_ENABLED flag), false in standard APKs. Test against an
isolated emulator or a subsequently verified secure deployment before enabling.

Features 8–14:

- Monthly category reports, spend bars, prior-month movement and audited category
  corrections. Voiding/restoring changes only metadata with matching immutable
  audit records; original amounts/items remain intact. Only the creator can
  change void state; members may correct categories. Grocery analytics observes
  void state and recomputes from events rather than mutable counters.
- Monthly group/category budgets, remaining/over-budget display, cached/pending
  indicators and quiet threshold banners. Native alerts/preferences follow in
  Phase 3. Budget revisions reject stale writes.
- Partial/full repayment records, references/receipt notes, exact remaining dues,
  immutable audit and one-time reversal records. Transfers are separate from
  spending. Payments apply only to their effective month; there is no accidental
  carry of settled balances into a new month.
- Recurring templates, enabled state, month-end clamping and explicit occurrence
  confirmation. Each template/month has one deterministic expense ID, enforced
  by rules. No template silently creates a financial expense.
- Personal spending lives under users/{uid}/personalExpenses with owner-only
  items and duplicate fingerprints. It is never written into shared expenses or
  the shared grocery library and never contributes to household settlement.
- Custom percentage/fixed-cent splits, including 60/40 and 100/0. Largest
  remainder allocation conserves cents. Equal shared 50/50 remains the default
  and retains existing monthly rounding. Refunds reduce cost and shares, rather
  than masquerading as repayments.
- Group-selected search with dates, merchant/item text in Greek/English,
  category, historical payer, amount bounds and optional own-private entries.
  Legacy item details remain searchable without requiring a destructive backfill.
  Changing the group filter re-creates the scoped repository/subscriptions.

Source expenses remain at their existing paths. New optional fields are additive
(scope, kind, category, splitCents, recurring identity); absent fields use v2
semantics. New collections are budgets, payments, recurring and expenseChanges.
Personal data is isolated beneath the account owner. No hard expense deletion is
provided. Rollback disables the feature gate and preserves additive records and
compatible restrictive rules. Do not revert to open rules or erase audit history.

Checks: analyze clean, 68 Flutter tests and 30 real Firestore emulator tests
passed. Standard Android debug build passed (3.0.0-phase.2+6). iOS source remains
compatible; no macOS/Xcode build or physical-device acceptance is claimed.
