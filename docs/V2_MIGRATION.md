# BashaHisab v2: before installation

This is an upgrade of com.bashahisab.app, version 2.0.0+2, using the same
Firebase project and iOS bundle ID (Com.bashahisab.app). Do not uninstall v1 or
clear app data just to upgrade. Install over it with the same signing certificate.
No production documents were changed by development or tests.

## Deployment order

1. Keep a normal Firestore backup/export before rollout. This upgrade does not
   delete or relocate any existing expense or item document.
2. Deploy **this version's firestore.rules** to the existing Firebase project
   before installing v2. Use Firebase Console → Firestore Database → Rules → paste
   the file → Publish, or an authenticated Firebase CLI:
   `firebase deploy --only firestore:rules --project YOUR_EXISTING_PROJECT_ID`.
   Native google-services/plist files are app config, not administrative deploy
   credentials. Rules have not been deployed by this code change.
3. Install the v2 debug APK over the existing debug APK. Sign in with the same
   email/password if necessary. Native Firebase Auth persists the session.
4. First signed-in launch adds/repairs the personal profile (uid, email,
   displayName, createdAt, updatedAt). Auth remains valid if Firestore is offline;
   the My Groups / Homes shell opens immediately with retry and cached streams.
5. If users/{uid}.householdId exists, a transaction creates
   users/{uid}/memberships/{groupId} and households/{groupId}/members/{uid} for
   that existing member, and writes legacyMembershipMigrated=true. The transaction
   is idempotent and retryable. It never reads/writes expenses or items. Legacy
   householdId/name/inviteCode fields remain immutable migration hints; the UI
   uses memberships instead. Each roommate migrates independently on first v2 use.
6. Verify the original group's historical months and totals on both devices.
   Upgrade both roommates before relying on the new group/leave functions.

## Data and access

households remains the group collection. memberIds is the atomic active-access
index; paired membership documents support independent personal accounts and
multiple groups. The default and client-enforced maximum is two active members.
maxMembers is stored explicitly for future schema expansion; supporting larger
groups later requires a deliberate rules/product change, not a profile migration.

Only the account owner can access their profile/private membership list. Member
records must be paired atomically and cannot grant access independently of the
household's validated memberIds. Joining requires the actual 128-bit invite code;
invite listing and ID-only joins are denied. Groups/expenses/items are private to
current members, including v1 members who have not migrated yet.

Leave removes only the caller's two membership documents and active ID. It keeps
the profile, household, names, all expenses, and all item documents. The first
leave freezes legacyMemberIds so older expense splits remain associated with
the original roommates. New expenses with two participants store splitBetween.
A replacement roommate never inherits earlier purchases. Historical participants
may still appear in balances; an all-empty group is retained but inaccessible
until someone rejoins with a valid invite. Keep invite codes private.

A migration marker prevents a future startup from undoing an intentional leave.
Locally remembered selections are scoped to the uid and are ignored when no
longer in the current membership list. Switching groups recreates the monthly
screen/subscriptions so one group's stream cannot supply another group's data.

## Compatibility and rollback

Existing authenticated v1 members can still read their existing households and
append expenses under the v2 rules. V1 creation/join flows depend on the old
identity model and are no longer supported after deployment. Do not revert the
rules to v1 after v2 accounts/groups are created: v2 profiles would lose access to
new flows. A code rollback requires keeping compatible rules and all additive
fields; do not delete membership records or expenses as a rollback technique.

If recovery fails, keep the account and use Try again after checking connection
and rules deployment. Do not delete/recreate the Auth user: its uid owns access.
No bulk production migration, Storage, paid OCR, or administrative data writes
are part of installation. Receipt images and enhanced derivatives are local;
only reviewed structured expense data is sent to Firestore. App-created
preprocessing files are deleted after OCR; the system picker may keep its cache.

## Verification and remaining device acceptance

Automated tests cover migration idempotency, Auth-only account recovery, multiple
homes, selection isolation, leaving/rejoining, former-payer balances, Greek and
English parser samples, decimal/date formats, image preprocessing, and mandatory
review. Real Firestore emulator tests run only against demo-bashahisab and cover
legacy access, paired membership enforcement, invite proof, capacity/concurrent
joins, isolation and expense/item validation.

The Android APK compiles the native Tesseract bridge and bundles ell+eng models.
A native Linux Tesseract smoke test checks rendered Greek/English fixtures using
those same models. This is not physical Android/iOS acceptance testing. iOS has
not been compiled on this Linux machine. On a Mac run pod install then
flutter build ios --no-codesign; verify camera/gallery and mixed-language OCR
on both actual platforms, including airplane mode, faint receipts and rotations.
The pinned iOS XCFramework is fetched only at development-time pod installation.
