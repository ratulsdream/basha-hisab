# BashaHisab

A Flutter Android/iOS app for **two roommates** sharing one household. Sign in with email/password, create a household, invite your roommate with a private code, and track shared spending in real time.

## Features

- Firebase Email/Password sign-up, sign-in, sign-out, and password reset.
- One immutable household per account, with at most two members. The first member can add expenses while waiting for their roommate.
- Manual expense entry or a camera/gallery receipt processed **on the device** using bundled Google ML Kit Latin text recognition. No Firebase Storage, image uploads, or cloud OCR.
- Mandatory receipt review/edit screen with merchant, date, payer, items, and total. Confirm corrections before saving. Item/total differences require explicit confirmation; taxes and discounts may explain them.
- Monthly spending, each roommate's paid amount and 50% share, precise who-owes-whom calculation, and expense history/details.
- Integer minor units for money. For an odd cent, the lexicographically first account ID receives the extra cent of the share; both shares add up exactly.
- Live Firestore streams, loading/error/retry states, and a cached-data indicator. Household operations require connectivity. Expense saves wait for server acknowledgement; keep the save screen open until connectivity returns.

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

## Use with your roommate

1. Both people create their own account.
2. One person chooses **Create**, enters a name and the household currency, then copies the invitation code.
3. The other person chooses **Join**, enters their own name, and pastes the code.
4. Tap **Add expense**, choose manual/camera/gallery, select who paid, and review/save.
5. Use the month arrows to view monthly spending and history. Settlement reports the reimbursement required for equal expense sharing; it does not record transfers or perform payments.

Currency is fixed for the household; no exchange-rate conversion is performed. Items are optional and prices represent whole line totals, including quantity. Expenses are append-only in this version. Membership/name changes, leaving a household, and expense edits/deletions are not exposed. Contact your Firebase administrator if incorrect data needs correction.

OCR accuracy depends on receipt quality. Latin-script recognition is supported; Bengali and other unsupported scripts require manual entry. ISO `YYYY-MM-DD` and day-first `DD/MM/YYYY` / `DD-MM-YYYY` dates are suggested. Ambiguous dates, unrecognized totals, discounts, quantities, and mixed layouts require review. Images are processed locally and may remain in platform-managed camera/picker cache; only the structured expense fields go to Firestore.

## Verification

See [the current verification report](docs/VERIFICATION.md) for verified APKs, checks actually run, and the cloud-only build exclusions caused by an outbound proxy failure.

```sh
dart format lib test
flutter analyze
flutter test
cd tool/rules-tests
npm ci
npm test
```

Dart tests exercise money validation, both settlement directions, equal/zero spending, odd cents, incomplete households, OCR extraction, and sign-in/setup-error screens. Firestore emulator tests exercise atomic creation/joining, simultaneous joins, third-member rejection, cross-household isolation, invitation enumeration denial, forged expenses, and membership immutability. Emulator tests use the `demo-bashahisab` project and never production data.

For device acceptance, use two actual accounts/devices: add an expense on each, verify both dashboards/history sync, confirm reversed payer totals and an odd-cent split, scan a real receipt from camera and gallery, correct its OCR, and verify the reviewed fields are saved. Test rejected permissions, airplane mode/reconnection, password reset, and signing out/in. Do not infer these device results from unit tests.

## GitHub Actions APK artifacts

`.github/workflows/android.yml` runs Flutter checks, builds **debug** and **release-test** APKs, and uploads each as a workflow artifact retained for 14 days. After pushing the committed code:

1. In repository **Settings → Secrets and variables → Actions**, add a secret named **`GOOGLE_SERVICES_JSON`** containing the complete raw contents of your Android config file (not base64).
2. Open **Actions → Android APK → Run workflow** or push to `main`.
3. Download `BashaHisab-debug-…` / `BashaHisab-release-test-…` from the run's **Artifacts**.

The APK jobs deliberately fail with a clear message if the config secret is missing; they never build against a fake Firebase project. Fork PRs do not receive repository secrets. Checks can still run independently. A separate workflow runs Firestore security tests using the local emulator without credentials.

## Firestore layout and access

- `users/{uid}`: the user's name, household ID, and invitation proof; private to that account.
- `households/{id}`: fixed currency, two-member limit, names, and private invitation code; readable only by members.
- `invites/{128-bit-code}`: household ID and owner; authenticated document-get only, no listing. Treat the code as private until the roommate joins.
- `households/{id}/expenses/{id}`: merchant, payer, UTC calendar date, month key, integer total, item count, creator, and server creation timestamp.

- `households/{id}/expenses/{id}/items/{index}`: individual item names and integer prices; saved atomically with the expense (up to 100 items). Separate item documents allow every item to be validated within Firestore’s rules budget.

Rules validate payload fields/types, month/date consistency, item contents and limits, household payer/creator membership, atomic invitation-based joining, and single-household membership. Images, OCR raw text, extra fields, third members, and expense updates/deletes are denied. Members can record an expense paid by either roommate. Administrators with server credentials bypass Firestore rules; protect that access separately.
