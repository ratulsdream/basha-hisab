# Published rules comparison and proposed activation

Review date: 2026-10-18. **Comparison completed; the owner subsequently approved
the exact rules-only deployment subject to a fresh baseline check. Execution and
post-deployment verification remain pending.** See
[the approval record and guarded helper](APPROVED_RULES_DEPLOYMENT.md). Both
production build flags remain false. No production documents were read, modified
or deleted during this review.

## Evidence and exact proposed policy

The owner ran the repository's read-only export helper in authenticated Google
Cloud Shell and supplied `BashaHisab-rules-review.zip`. The archive contains only
the published rules and release metadata. The source SHA-256 matches that metadata.
This environment still has no Firebase administrative sign-in; this review uses
the supplied export, not a new live connection or a guarantee against later changes.

| Evidence | Value |
|---|---|
| Firebase project | `bashahisab-a6dd6` |
| Exported release | `projects/bashahisab-a6dd6/releases/cloud.firestore` |
| Published update time | `2026-10-16T08:37:42.586308Z` |
| Exported ruleset | `69a9477e-5c94-4c44-a0c0-d5abc2c26759` |
| Published source SHA-256 | `8f92d9c6e9fdb9ff292ec3e803b266e7e87859f0d2e1deb15ae99052eb053a7d` |
| Proposed source SHA-256 | `c0ece12ebca45c856fb3d053be07ab10a96be3ce6389cbae7dc035167e35d579` |
| Reviewed source commit | `7c6ffd859c2cf8a1592d832d1eb5bb67cbb76470` |

Exact proposed file: [firestore.rules at the reviewed commit](https://github.com/ratulsdream/basha-hisab/blob/7c6ffd859c2cf8a1592d832d1eb5bb67cbb76470/firestore.rules).
The review does not change this candidate file. Keep the owner's original ZIP as
the pre-deployment rules backup; it contains no expense-data backup.

## Why the app remains gated

Published rules support personal profiles, group membership, invitations, shared
expenses and their receipt items. Unmatched paths are denied. They have no rules
for the new v3 collections, so even legitimate group members cannot use them.
The app's compile-time gate is separate: changing flags cannot grant database
permission, and deploying rules alone will not enable a previously built APK.

## Proposed changes

| Feature | Proposed permissions and validation |
|---|---|
| Item library, Regular Items, price history | Group members read catalog, aliases and purchase index; purchase details must match a source receipt. Corrections/merges use revisions and paired audit records. |
| Shopping List | Group members use shopping entries/events; validate quantities, units, assignment, revisions and paired add events. |
| Kitchen Inventory | Group members use stock/events; receipt-backed restock and consumption require paired events, quantities cannot become negative, repeated event IDs cannot replay changes. |
| Budget and recurring bills | Group members use validated monthly/category budgets and recurring templates; revisions and stable recurring expense IDs prevent supported retry duplicates. |
| Settlement/payment history | Group members read and create validated, immutable payment records and exact one-time reversals. These are roommate-entered records, not bank-confirmed payments. |
| Personal spending and duplicate detection | Only the account owner accesses personal expenses/items/signatures; shared receipt signatures remain group-scoped. No receipt image storage is added. |
| Notification preferences/devices | Only the account owner accesses their preferences and device records. This does not deploy a push server or configure APNs. |
| Expense schema | Accept validated optional category, shared scope, refund, exact custom shares and recurrence fields; receipt items accept optional quantity/unit pairs. Legacy payloads remain accepted. |
| Expense corrections | Members may change category with a matching immutable audit. Only the creator can void/restore an expense. Original amount, payer, date and items remain immutable; deletion remains denied. |

There are 16 added group subcollections (the cross-group test matrix covers 17
including existing expenses). No blanket signed-in-user read/write rule is added.
The final default-deny rule remains in place.

Account/profile ownership, membership authority via `memberIds`, paired membership
documents, invite requirements, two-member capacity, and leave protection are
unchanged. Unknown paths remain denied.

## Tests against both policies

The same 33-test suite ran separately against the official Firestore emulator
on localhost using `demo-bashahisab`. The exported policy was loaded from a
temporary test working directory; its SHA-256 was checked before the run. No
production connection or data was used.

| Policy | Passed | Failed |
|---|---:|---:|
| Proposed repository rules | 33 | 0 |
| Exported published rules | 18 | 15 |

All 18 existing account, group, invitation, expense, receipt-item and migration
scenarios pass with both policies. These include cross-group expense denial,
third-member rejection, forged membership denial, legacy membership migration,
and leave/rejoin preserving expenses.

The 15 v3 scenarios fail with published rules because the expected legitimate
operations are denied. The two v3 access matrices fail at their permitted member
setup/read, not because an outsider gained access. Both complete matrices pass
with the candidate, including cross-group denial and access revocation on leave.

The prior real FlutterFire/Auth/Firestore integration scenario passed in Actions
run [39118754893](https://github.com/ratulsdream/basha-hisab/actions/runs/39118754893)
with this same candidate rules hash. That is prior isolated SDK evidence, not a
new production or physical-phone acceptance test. Actual production document
contents and any unusual historical admin imports were not inspected.

## Preservation and migration

Publishing rules changes permissions; it does not rewrite database documents.
The proposed policy preserves reads of existing authorized group expenses and
accepts legacy expense creation shapes. No bulk data conversion is needed.

Existing account recovery merges identity fields. Legacy membership migration
creates paired access records only for existing members, then records completion
once; it does not change expenses or rejoin someone who intentionally left.

Historical library indexing is a separate explicit **Import historical items**
action. It adds derived catalog/purchase records using deterministic IDs and is
repeat-safe. It does not replace source expenses/items. Old receipts without
item details cannot supply item history that was never recorded.

## Approval scope and next steps

The proposed authorization is **only** deployment of the exact candidate
`firestore.rules` hash above to `bashahisab-a6dd6`. It includes the expense
correction permissions described above. It excludes indexes, Functions, Storage,
all document modifications, and any unrelated Firebase project.

1. Obtain the owner's explicit approval for this project and exact candidate.
2. In the owner's authenticated Cloud Shell, re-export the live rules immediately
   before deployment. Stop and compare again if the release/ruleset/source changed
   from this reviewed export. Verify the candidate's hash too. Preserve the ZIP.
3. Use a rules-only Firebase CLI deployment (`--only firestore:rules`) with the
   explicit project ID. Do not use a general `firestore` or full-project deploy:
   the repository index file is empty and live indexes have not been reviewed.
4. Re-export the published rules and require an exact match to the approved hash.
   If verification fails, keep app gates closed and investigate before activation.
5. Build a test APK with both `V3_ENABLED=true` and `V3_ITEMS_ENABLED=true`, validate
   the enabled configuration, and provide a downloadable artifact. Share that
   updated APK with both roommates before using new financial features.
6. Check the enabled features on Android. Any production acceptance writes must
   use an explicitly agreed test group/accounts; do not silently add test records
   to the user's real household. Keep iOS compatibility and report device limits.

No deployment command was executed or supplied before approval. The approved
helper now uses only the official Rules API operations; see the approval record
for its tighter executable scope. Existing flags remain closed. Remote notifications/APNs and
physical-device acceptance are separate from this permission-policy comparison.

Rollback: preserve the exact original rules export and all data. If necessary,
pause new entry routes and seek approval for a rules rollback or forward fix.
Restoring old rules would hide v3 collections rather than delete them. Once
refunds, custom splits or payments exist, an old v2 APK is not a reliable
financial rollback because it does not understand those records.
