# Phase 0 — safety baseline

Repository rules were reviewed and emulator-tested. They use memberIds as the
atomic group access authority; paired records enforce join/leave consistency.
Profiles and private memberships are owner-only. Invitations are unguessable and
get-only, two concurrent joiners cannot exceed capacity, and expenses/items are
validated and immutable. Unrecognized invoice/receipt/settlement paths default
to deny. No blanket authenticated-user rule exists. No production rules/data
have been changed.

Deployed-rules comparison is BLOCKED until the owner supplies the Console rules
or an authenticated administrative read connection. Firebase app configuration
is insufficient. Save the deployed rules outside Git and run:
`python3 tool/security/audit_rules.py --deployed-rules /tmp/deployed.rules`.
A hash match must correspond to the phase's emulator-tested rules. A hash
comparison alone is not a replacement for authorization tests. Do not enable
new production modules until the deployed audit and secure rules rollout pass.

V1/v2 migrations remain additive and idempotent. Phase 0 fixes expense retry:
a transaction recognizes identical already-committed data (including item
contents) and refuses the same ID with different content. It never overwrites
or deletes a historical expense. Initial writes remain atomic. Transactions
require connectivity; Phase 3 supplies the durable offline outbox.

No account/group/receipt/expense/settlement deletion or bulk backfill runs at
startup. Later indexes must use deterministic IDs, explicit reviewed backfill,
per-item source events, progress/retry, and tombstones rather than data removal.
Rollback keeps additive fields/collections and compatible rules. Never roll back
to broad rules to make a module appear to work.

Existing synthetic Greek/English receipt fixtures and the scan-flow regression
cover ell+eng assets and required review. Real Cyprus receipt/device acceptance
still requires owner testing; no private receipts were copied from production.
Phase 0 APK retains v2 functionality; new modules are not enabled in production.
