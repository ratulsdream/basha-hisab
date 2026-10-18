BashaHisab v2 bundles tessdata_fast 4.1.0 Greek and English models (Apache-2.0),
and uses Tesseract (Apache-2.0), Leptonica (BSD-2-Clause), and
Tesseract4Android (Apache-2.0). The Android native AAR was redistributed from
flutter_tesseract_ocr 0.4.31 (BSD-3-Clause); its redistribution license is retained
at packages/local_receipt_ocr/LICENSE. The iOS engine is the pinned official
SwiftyTesseract/libtesseract 0.2.0 XCFramework (Apache-2.0).

Sources and model hashes are recorded beside these dependencies. Flutter's
LicenseRegistry includes the bundled OCR notices at startup; the profile has an
Open source licenses entry. Test-only fake_cloud_firestore 4.1.1 retains its MIT
license in tool/test_support/fake_cloud_firestore/LICENSE.

Upstream license texts:
- https://github.com/tesseract-ocr/tesseract/blob/main/LICENSE
- https://github.com/DanBloomberg/leptonica/blob/master/leptonica-license.txt
- https://github.com/adaptech-cz/Tesseract4Android/blob/master/LICENSE


The 3.1 interface bundles Noto Sans Bengali regular/bold (SIL Open Font License;
full notices in assets/fonts/NOTO-LICENSE.txt). DejaVu Sans supports Greek PDF
exports and UI fallback (assets/fonts/LICENSE.txt). Both are registered in the
app's open-source license view. Firebase browser SDK 12.19.0 and esbuild are
locked test-only dependencies; their temporary SDK bundle is not an app asset.
