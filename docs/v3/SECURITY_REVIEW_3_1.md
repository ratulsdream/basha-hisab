# 3.1 security review and production activation checklist

## Current outcome

Repository audit and isolated tests are complete. Production verification and
activation CANNOT complete without the actual published rules. No Firebase CLI
account/tokens, gcloud executable or Google application-default credentials are
available in this environment. Native google-services.json and iOS plist are
app configuration, not permission to export or publish security rules. GitHub
access does not grant Firebase administration.

No production rules, documents, indexes, Functions or remote configuration have
been deployed, replaced or deleted. The dashboard uses existing reads and the
same additive account recovery; simply viewing it writes no financial data.
V3_ENABLED and V3_ITEMS_ENABLED remain false in normal builds. A different UI
state does not confer database access. Rules are always the server authority.

## Beginner-friendly: provide the published rules

The easiest method needs a computer for a few minutes:

1. Open https://console.firebase.google.com and choose the same project shown
   by your existing BashaHisab app. Do not create a new project.
2. Open **Build → Firestore Database → Rules**.
3. Confirm you are looking at the **currently published** version, not an
   unpublished editor draft. Note the displayed published date/time and project ID.
4. Click inside the rules editor. Press **Ctrl+A, Ctrl+C** (Mac: Cmd+A, Cmd+C).
   Paste into a plain text file named **deployed-firestore.rules**.
5. Attach that file here with the project ID and published date/time. It is okay
   if it is long. Do **not** tap Publish, restore an older version, edit the rules
   or send Firebase passwords, OAuth codes, private keys or access tokens.

If you only have Android: Chrome → Firebase Console → Chrome ⋮ → **Desktop site**
→ Firestore Database → Rules. If selecting the complete editor is awkward, use
an available computer; screenshots of part of the rules cannot verify the full
policy. No changes are needed in your working database while you arrange this.

Optional authenticated export for someone with gcloud already configured:

```
python3 tool/security/export_deployed_rules.py --project YOUR_PROJECT_ID --output /tmp/deployed-firestore.rules
python3 tool/security/audit_rules.py --deployed-rules /tmp/deployed-firestore.rules
```

The helper makes exactly two read-only Firebase Rules API GET requests: current
cloud.firestore release, then its ruleset. It uses existing gcloud credentials
in memory and exports source plus release/ruleset/time/hash metadata. It never
calls deployment APIs or reads expense documents. Use Firebase Rules Viewer
(`roles/firebaserules.viewer`) access for this operation. Keep administrator
credentials in secure environment settings or your terminal, never in chat/Git.
A Console copy must be checked against its published version; whitespace/hash
differences require human review and do not prove that either policy is secure.

## Repository policy audit

- Group reads use the atomic households/{id}.memberIds authority. This preserves
  legacy members before paired membership documents are created. Each sensitive
  subcollection calls member(id), not a blanket authenticated-user condition.
- users/{uid} profile, memberships, personalExpenses/items, private receipt
  signatures, notification preferences and device tokens are owner-only. Group
  members cannot read another member's private spending or tokens.
- Joined groups require the 128-bit get-only bearer invite, matching paired
  membership records and a group update adding only the caller. Capacity is two;
  concurrent joins cannot add a third. Knowing a group ID alone is insufficient.
- Leaving removes only the caller's access records and membership entry, preserves
  historical names/legacy participants and all expense/item/payment documents.
  Multi-group membership does not confer cross-group access.
- Source expense amount/items are immutable. Category/void edits require matched
  immutable audit entries; only the creator may void/restore. Dates/months,
  exact custom shares, refund kinds, payer membership and field shapes validate.
- Derived purchases must match an existing same-group source expense and line;
  deterministic IDs prevent duplicate indexing. Corrections, aliases, catalog
  merges and stock mutations require paired event/audit records and revisions.
  Reviewed restock is once per source purchase; consumption cannot go negative.
- Payment/reversal records are immutable and group-scoped. Budget and recurring
  templates use revision checks. Recurring occurrence IDs prevent duplicate saves.
  These are roommate-entered records, not bank-verified transfers.
- Unknown receipts/invoices/settlements paths and server notification-delivery
  records default deny. No Firebase Storage or receipt image upload is added.

Dashboard access inventory:

| UI | Read paths | Required access |
|---|---|---|
| Home/history | household; expenses and item details | Current group member |
| Enabled settlement/budget | payments, budgets | Current group member |
| Enabled regular preview | catalog, purchases, purchaseCorrections, expenses | Current group member |
| Enabled shopping/inventory/prices | shopping/events, stock/events, catalog/purchases | Current group member |
| Private spending/export | users/{uid}/personalExpenses/items | Owner only |
| More notification preferences | users/{uid}/preferences/devices | Owner only |
| Offline drafts; language/theme | Account-scoped SQLite; local preferences | Local device, no rules bypass |

Migration: ensureProfile updates only additive identity fields; a transaction
creates paired legacy memberships only for a UID already in the original group's
memberIds. It leaves original expenses/items untouched and marks migration once,
so a later intentional leave is not undone. Joins/leaves are atomic. No new bulk
migration is needed for the dashboard. Historical administrators' malformed or
partially imported records must be reviewed, not destructively repaired on startup.

## Isolated tests and limits

Run the official Firestore emulator against demo-bashahisab, not a production
project. The suite exercises supported writes and adversarial cross-group reads,
queries and writes across every v3 collection, leave/revocation, capacity races,
forged memberships, legacy migration, immutable sources, private spending and
financial/stock audit rules. The two new matrix tests also assert retained
historical documents after leave.

Run `flutter test --dart-define=V3_ENABLED=true`: Flutter widget/domain tests use
an injected FakeFirebaseFirestore and MockFirebaseAuth, with enabled modules.
The official security suite separately uses the real Firestore emulator. These
are complementary checks; fake Firestore does not enforce rules. This is NOT a
claim that a physical Android/iPhone application has been exercised end-to-end
against Firebase. Physical camera/gallery, actual offline reconnect, OS permission,
APNs and iOS/Xcode checks remain device/Mac acceptance work.

## Production approval and activation sequence (not performed)

1. Obtain the current published rules plus project/release metadata. Compare each
   access path above and the complete source with the emulator-tested candidate.
2. Resolve any differing or additional production collections, validate known
   legacy shapes and test a non-production copy of representative records.
3. Present the exact rules/index diff, project ID, rules hash and rollback plan
   for the owner's explicit approval. No approval is inferred from asking for UI
   redesign or from a missing permission error.
4. Only after that approval may an authorized administrator deploy the reviewed
   rule/index change. Export again to confirm the exact published source/hash.
5. Recheck positive/negative access with two test accounts; verify all enabled
   paths including cross-group denials. Retain a backup of source data/rules.
6. Only then build production with --dart-define=V3_ENABLED=true for the verified
   modules. This change deliberately does not alter the production build flags.
   Remote push remains a separate opt-in server/APNs configuration step.

Never fix access by publishing broad authenticated-user rules. Rollback preserves
all additive records. Once custom splits/refunds/payments exist, old v2 code
cannot be treated as a correct financial rollback; fix forward or disable new
entry routes while retaining the data and secure rules.


Additional real-SDK check: test/emulator/repository_emulator_browser_test.dart uses
real named Firebase apps, Auth emulator email/password accounts, and the actual
HouseholdRepository/ItemsRepository/PlanningRepository with V3_ENABLED=true.
Every app uses hardcoded demo-bashahisab and localhost endpoints, never the native
production config. It tests join, duplicate-safe expense save and indexing,
reviewed restock/consume retry, budget, repayment, private/cross-group denial,
multiple memberships and leave while retaining original expenses.

Local execution was initially blocked by missing web SDK downloads and network
HTTP 403 for storage.googleapis.com, storage.flutter-io.cn and www.gstatic.com.
No checksum or TLS checks were disabled. The delivery workflow runs the test in
GitHub Actions and publishes the dashboard APK only after it passes; the bot's
status file reports the outcome. These SDK-level browser checks still do not
claim a physical Android/iPhone end-to-end test.

Reproduce on a machine with Flutter web SDK, Chrome, Java 21, Node 22 and internet:

```
flutter pub get --enforce-lockfile
npm ci --prefix tool/rules-tests
tool/run_web_repository_tests.sh
```

Reviewed repository rules SHA-256: `c0ece12ebca45c856fb3d053be07ab10a96be3ce6389cbae7dc035167e35d579`. This identifies the candidate, not the deployed production policy.


The browser integration harness serves the integrity-locked npm Firebase 12.19.0
SDK (matching firebase_core_web's supported version) from a temporary loopback
module server, rather than depending on runtime CDN imports. This is the genuine
SDK, not a fake backend or a security bypass. The bundle is test-only and is not
an Android/iOS app asset. npm ci verifies its lockfile integrity. The helper
starts/stops its own temporary server and Auth/Firestore emulators, all on local
ports, and never loads production native configuration.


Real SDK integration result: PASSED in Actions run 39118754893 (1 full repository
scenario; account recovery/profile, join, expense retry/indexing, stock events,
budget/repayment, private and cross-group denial, multi-group membership, leave
and original expense retention). The browser runner explicitly registers genuine
FlutterFire web implementations. Full standard Firestore and optional pipeline
exports are supplied from the same locked SDK version; no fake backend or rule
bypass is used. Native Android/iOS device acceptance remains separate.

The legacy V3_ITEMS_ENABLED compatibility flag currently maps to the master v3
gate, including planning. It is not a limited permission grant. Verify every
path in the inventory before enabling either flag. Partial module approval
requires separately scoped capabilities before activation; normal builds keep
both flags false.
