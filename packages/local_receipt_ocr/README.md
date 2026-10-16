# Local receipt OCR

Small BashaHisab-owned method-channel bridge. Both implementations initialize
Tesseract with **ell+eng**, OEM_LSTM_ONLY, PSM_AUTO, on a serial background worker.
No Vision fallback, Latin ML Kit, HTTP upload, or runtime model download is used.
Dart copies pinned tessdata_fast 4.1.0 assets into application support and sends
only local PNG paths to the engine. Each engine instance is destroyed after use.

Android: tesseract4android-release.aar distributed in flutter_tesseract_ocr
0.4.31 (https://pub.dev/packages/flutter_tesseract_ocr/versions/0.4.31), upstream
https://github.com/adaptech-cz/Tesseract4Android. This is a prebuilt upstream
native dependency; do not hand-edit its bytes. The Java bridge is maintained
here rather than patching a user's pub cache.

iOS: official SwiftyTesseract libtesseract 0.2.0 XCFramework, fetched at pod
installation, pinned by SHA-256 in BashaTesseract.podspec. Direct Tesseract and
Leptonica C APIs avoid wrapper fallback and use the actual local language-data
path. Framework archive SHA-256:
cc42f3424047adc7064e6bb67d5039385629ee42199fcbb0553f57f1110d8c90.

Upstream notices: Tesseract Apache-2.0; Leptonica BSD-2-Clause; package
redistribution BSD-3-Clause (LICENSE). Models: Apache-2.0, see the bundled
assets/tessdata/LICENSE. See THIRD_PARTY_NOTICES.md in the app repository.

The Android bridge is compiled by the APK build. The iOS bridge requires a Mac
with Xcode: run `pod install` under ios then `flutter build ios --no-codesign`.
Physical-device smoke tests must include mixed Greek/English receipts, faint
thermal print, rotated photos, cancellation, and airplane mode. OCR accuracy is
not guaranteed; explicit review is always required.
