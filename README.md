# BashaHisab v3 — Smart Household Edition

Incremental issue #1 implementation: [phase tracker](docs/v3/STATUS.md), [Phase 0](docs/v3/PHASE_0.md), [Phase 1](docs/v3/PHASE_1.md). Production rules are not deployed automatically; new modules default to a closed security gate pending deployed-rule verification.

Flutter Android/iOS shared expenses, upgraded in place from v1. Personal Firebase
Email/Password accounts can belong to multiple Groups / Homes. Each new group
currently holds two roommates and uses equal splitting. Existing Firestore
expenses remain at their original paths.

**Before installing: read [v2 migration/deployment steps](docs/V2_MIGRATION.md).**
Deploy the new Firestore rules first. Production rules/data are not automatically
changed by building the app.

## Features

- Permanent personal profile, create/join/leave homes, group switching, private
  invite copy/share, and last selection remembered per account.
- Auth session persistence, trimmed/lowercase email, guarded submissions, timeout,
  one retry of transient network failures, password reset and partial-registration
  recovery. The signed-in shell appears before Firestore profile work completes.
- Offline Greek + English Tesseract OCR with bundled Modern Greek ell and English
  eng models on Android/iOS. EXIF correction, bounded resizing, grayscale,
  contrast normalization and sharpening run off the UI isolate. Original/enhanced
  passes are scored; duplicate item lists are never blindly concatenated.
- Review every scan before saving. Raw text from both passes, uncertain-field
  warnings, editable items, and items-sum/total comparison. Greek/English total,
  tax/payment vocabulary, European dates and European/US money formats.
- Live monthly spending/history, paid amounts, equal shares and debt transfers.
  Departed payer names and original expense participants are retained.
- Receipts stay local: no Firebase Storage, image upload or normal cloud OCR.
- Separate auth, groups/profile, receipt and expense features; append-only expense
  and item data with tested Firestore membership rules.

## Local setup

Use Flutter **3.35.7**, Java 17 or 21, Android SDK platform 36, build tools 35.0.0, and NDK 27.0.12077973. The project pins Firebase Core 4.15.0, Auth 6.7.0, Firestore 6.10.0, Kotlin 2.3.0, Android Gradle Plugin 8.13.2, and Gradle 8.13. Android minimum SDK is 24. iOS requires macOS, Xcode, CocoaPods, and iOS 15.5+. Run `flutter doctor` to check your toolchain.

```sh
flutter pub get
```

Firebase native config files are ignored by Git. The Android package is **`com.bashahisab.app`**. The supplied Firebase iOS bundle ID is **`Com.bashahisab.app`** (capital `C`); the project uses that exact case-sensitive value.

Download your own platform files from the **same Firebase project**, then install/validate them:

```sh
python3 tool/configure_firebase.py \
  --android /path/to/google-services.json \
  --ios /path/to/GoogleService-Info.plist
```

The helper verifies the Android package, matching Firebase projects, and required keys; copies the files into their native locations; and sets all iOS app/test bundle settings from the plist. The iOS plist is already registered in the Runner resource build phase. Do not substitute a guessed bundle ID. Never commit service-account credentials or signing keys.

In Firebase Console:

1. Enable **Authentication → Sign-in method → Email/Password**.
2. Create **Cloud Firestore** in the intended project/region.
3. Deploy the rules in this repository (not open test-mode rules):

   ```sh
   cd tool/rules-tests
   npm ci
   npx firebase login
   npx firebase deploy --only firestore --project YOUR_FIREBASE_PROJECT_ID --config ../../firebase.json
   ```

   Deployment requires your Firebase account permissions. Native app config files do not grant deployment access. The only expense query is a single-field month filter, so no composite index is required.

Run:

```sh
flutter run
# Android APKs (the supplied Firebase config must be installed first):
flutter build apk --debug
flutter build apk --release
```

The release build currently uses **debug signing for release testing only**. Configure a private production keystore and signing configuration before Play Store distribution. For iOS, open `ios/Runner.xcworkspace`, set your Apple development team, run `pod install` in `ios/`, and build/run using a physical device. Camera and photo usage descriptions are included. Linux cannot build or sign iOS apps.

## Use

1. Sign up or sign in with your existing email/password.
2. On **My Groups / Homes**, choose **Create group** or **Join with invite code**.
3. Use the profile icon to edit your personal display name. Share the invite from
   the home screen. Use **Switch group** to return to your homes.
4. Tap **Add expense** for manual entry, camera or gallery. Review and confirm OCR
   before saving; use whole line totals including quantity.
5. Browse months and settlement. Leaving preserves all group history and your
   account, but removes your access. Rejoining requires a valid invitation.

Currency stays fixed; there is no exchange-rate conversion. Expenses are
append-only, and reimbursement transfers are displayed rather than recorded as
payments. OCR remains a suggestion and depends on image quality. Moderate deskew
is not attempted automatically because rotating a faint receipt can destroy text.

## Checks and APKs

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test packages/local_receipt_ocr/lib
flutter analyze
flutter test
python3 tool/ocr_smoke.py # optional native smoke test, needs Tesseract 4+
cd tool/rules-tests
npm ci
npm test
```

Android CI checks format/analyze/tests, builds debug and release-test APKs, and
uploads artifacts. Set repository Actions secret GOOGLE_SERVICES_JSON to the raw
Android Firebase config, then Actions → Android APK → Run workflow. Download
BashaHisab-debug-… from the successful run's Artifacts, extract the ZIP, and tap
the APK. The release-test build uses debug signing, not a production store key.
A separate workflow runs the Firestore emulator tests without production access.

Read [v2 migration](docs/V2_MIGRATION.md), [verification](docs/VERIFICATION_V2.md),
[native OCR implementation](packages/local_receipt_ocr/README.md), and
[third-party notices](THIRD_PARTY_NOTICES.md). Physical camera/gallery, two-device
sync and iOS builds require device/Mac acceptance checks; unit tests do not claim
those results. The v1 verification report remains under docs for historical use.

## Firestore schema

- users/{uid}: uid, email, displayName, createdAt, updatedAt; optional immutable
  legacy identity hints and a one-time migration marker.
- users/{uid}/memberships/{groupId} and households/{groupId}/members/{uid}:
  paired uid, groupId, displayName, joinedAt, inviteCode records.
- households/{groupId}: title, maxMembers (2), active memberIds, historical
  memberNames, currency, inviteCode, createdAt; optional frozen legacyMemberIds.
- invites/{128-bit-code}: householdId, ownerId, createdAt; authenticated get only.
- households/{groupId}/expenses/{expenseId}: unchanged v1 fields, with optional
  additive splitBetween on v2 expenses. Items remain in items/{index}.

Private profile/membership lists belong to their owner. Only active group members
read group data. Joining, leaving and paired records are enforced atomically;
third-member additions, ID-only joins, forged creators/payers and image/raw-text
fields on expenses are rejected. Max-member limits are explicit in the data
layer so a later product version can expand them with corresponding rules.
