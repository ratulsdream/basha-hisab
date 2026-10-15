# BashaHisab test APKs

On an Android phone, expand **Assets** below and tap **BashaHisab-debug.apk** for the debug app, or **BashaHisab-release-test.apk** for the optimized release-test app.

These are the already-built, signed APKs from app source commit 33e774d. No app rebuild was performed for this release. Both use Android package com.bashahisab.app and the same test signing certificate. Android 7.0 / API 24 or newer is required.

The release-test APK is debug-signed for testing, not Play Store distribution. Local cached builds omitted Android library annotation/AAR publishing metadata and native Android lint after an outbound network failure; Dart analysis, 19 Flutter tests, and 10 Firestore security tests passed. Real-device OCR/Firebase syncing and iOS native builds still need device validation. OCR supports Latin-script receipts, with mandatory review and manual correction.

APK SHA-256 checksums:

- BashaHisab-debug.apk: 7b95903ee438b1ec861da6e0a37d3203e922806cf82addd020a4bd8490754b65
- BashaHisab-release-test.apk: 78582e628da11187c26b97185e79d6d17557b36fb83548e156a4feb18209113a
