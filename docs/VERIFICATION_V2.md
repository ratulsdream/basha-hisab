# BashaHisab v2 verification — 2026-10-16

- Flutter 3.35.7 / Dart 3.9.2, same Android/iOS app identifiers and Firebase config.
- `flutter analyze`: **no issues**.
- `flutter test --reporter expanded`: **43 passed**, none skipped. Includes Auth
  registration recovery, duplicate-submit guard, transient retry, profile recovery,
  legacy migration/retry/leave, multiple memberships, local group selection,
  immediate groups shell, Greek/English receipts, total keywords and OCR glyph
  confusion, date/decimal formats, EXIF rotation, preprocessing, monthly rounding,
  former/replacement roommates, and mandatory review/edit before save.
- Real Firestore emulator against demo-bashahisab: **16 passed**, none skipped.
  Includes legacy accounts/expense preservation, independent profiles, multiple
  homes, paired records, unauthorized joins, simultaneous joins/default capacity,
  leave/rejoin/access revocation, immutable historical participants, forged
  splits, and 100-item atomic expense writes within the rules budget.
- `python3 tool/ocr_smoke.py`: both rendered Greek and English fixtures passed
  using the bundled ell+eng models with native Linux Tesseract. Fixtures are
  synthetic test receipts, not user data.
- `flutter build apk --debug`: **passed**, using ordinary Flutter build with no
  annotation/lint task exclusions. Cloud Flutter Maven packaging uses the same
  verified cache override described in the v1 report; no engine bytes changed.
- `apksigner verify --verbose --print-certs`: **passed**. Signing certificate
  matches the retained v1 release-test APK, enabling an in-place Android upgrade.
- `aapt dump badging`: com.bashahisab.app, versionName 2.0.0, versionCode 2,
  minSdk 24, target/compileSdk 36.
- APK contains byte-identical bundled ell and eng language models, and native
  libtesseract.so for arm64-v8a, armeabi-v7a and x86_64.
- Actionlint: all workflows passed. Delivery workflow uploads the existing
  verified debug APK without building it again.

APK: build/app/outputs/flutter-apk/app-debug.apk

Size: 207,269,863 bytes

SHA-256: 6cf22d5ca4704c2c3ff0888665356da1e39c29b45680ea2661605533f241c65d

The iOS XCFramework archive was downloaded and its pinned SHA-256 verified.
Its exported Tesseract/Leptonica headers were inspected for the bridge API.
iOS compilation/signing and physical Android/iOS camera/gallery, airplane-mode
OCR, and two-device Firebase sync have **not** been executed in this Linux
workspace. Run these acceptance checks on devices before production rollout.

No production Firebase rules or documents were changed. Deploy the v2 rules
before installing: see V2_MIGRATION.md. No v2 release-test APK was requested or
built; the prior v1 release-test APK is not a v2 deliverable.

A test-only fake_cloud_firestore patch is documented under
`tool/test_support/fake_cloud_firestore/PATCH.md`; the actual security checks use
the official emulator rather than this fake. The third-party fake is excluded
from app linting; application, native plugin Dart, and first-party tests are
analyzed normally.
