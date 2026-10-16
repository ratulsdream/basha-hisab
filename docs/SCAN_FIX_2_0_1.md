# Receipt selection failure fixed in 2.0.1+3

The v2 scanner called Directory('$cache/receipt-').createTemp(). Dart creates
temporary directories *inside* the receiver, so this failed with
PathNotFoundException because cache/receipt- did not exist. The exception occurred
before preprocessing or native OCR, after successful camera/gallery selection.
The UI then incorrectly suggested checking camera/photo permissions.

The scanner now calls cache.createTemp('receipt-') on the existing cache
directory. Regression tests exercise the complete file/model/preprocessing/OCR
orchestration using real bundled models and fixture images with a recording
native-engine substitute. They assert that both OCR passes are reached and all
image derivatives are removed after success and after engine errors.

The Android engine constructor is also inside the error handler, and native
library load errors are returned to Dart instead of leaving the scan Future
pending. Error messages distinguish local-file, image-format, permission, model,
and native-runtime failures without exposing local paths or receipt contents.

Verification: Flutter analyze clean; 46 Flutter tests passed. This patch changes
no Firebase data model, security rules, migration, account, membership, or expense
records. Install over the existing app; do not clear its data or uninstall it.
Physical-device receipt acceptance testing is still required; host tests do not
claim to reproduce every camera or device-specific native issue.
