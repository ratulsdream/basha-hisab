# Verification status

Verified in the cloud workspace on 2026-10-15:

- Flutter 3.35.7 / Dart 3.9.2, Kotlin 2.3.0, Android Gradle Plugin 8.13.2, Gradle 8.13.
- `flutter pub get --offline --enforce-lockfile`: passed with the committed lockfile and prepared dependency cache; repeated installation passed.
- `dart format --output=none --set-exit-if-changed lib test`: passed.
- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --no-pub --reporter expanded`: **19 passed**, none skipped.
- Firestore security tests against a fresh local emulator: **10 passed**, none skipped. Includes two simultaneous joiners, 100 atomic receipt item writes, unauthorized access, and malformed data.
- `./gradlew :app:compileDebugKotlin --offline`: passed for the app and native plugin Java/Kotlin compilation (138 tasks, 4 executed and 134 up-to-date).
- Native XML/plist files parsed; supplied Android/iOS Firebase configs validated as the same project. Android package `com.bashahisab.app`; exact supplied iOS bundle `Com.bashahisab.app`.
- Gradle wrapper JAR/distribution checksums verified against Gradle's official published checksums.
- GitHub Actions workflow YAML parsed successfully.

## Android APKs

The **debug APK was built successfully** from the retained verified dependency cache:

```sh
cd android
./gradlew :app:assembleDebug --offline --console=plain -x extractDebugAnnotations
```

The local exclusion skips Android library annotation-metadata extraction, whose external tooling dependencies could not be downloaded. It does not skip app compilation, dexing, native/resource packaging, or signing. The full CI workflow uses ordinary `flutter build apk` commands with this task enabled.

Output: `build/app/outputs/flutter-apk/app-debug.apk` (181,153,413 bytes).

- `apksigner verify --verbose`: passed.
- APK package ID and application label checked using `aapt`: `com.bashahisab.app`, `BashaHisab`.
- Bundled on-device OCR model assets: 21 files verified in the APK.
- SHA-256: `7b95903ee438b1ec861da6e0a37d3203e922806cf82addd020a4bd8490754b65`.

The **release-test APK was also built successfully**, with Dart AOT compilation, R8 minification, resource optimization, native ABI packaging, and signing enabled:

```sh
cd android
./gradlew :app:assembleRelease --offline --console=plain \
  -x extractReleaseAnnotations -x bundleReleaseAar -x syncReleaseLibJars \
  -x lintVitalAnalyzeRelease -x lintVitalReportRelease -x lintVitalRelease
```

The local release command excludes **library AAR/annotation publishing metadata and native Android lint**, whose external tooling downloads are unavailable. These optional tasks are **not verified**; no failed checks are relabeled as passed. The app's compilation, R8, resource/native packaging, and signing tasks completed. The CI workflow retains normal full Flutter builds without these exclusions.

Output: `build/app/outputs/flutter-apk/app-release.apk` (82,646,333 bytes).

- `apksigner verify --verbose --print-certs`: passed for both APKs, with matching test signing certificates.
- Release APK verified as non-debuggable, package `com.bashahisab.app`, minimum SDK 24.
- Release includes AOT libraries for `armeabi-v7a`, `arm64-v8a`, and `x86_64`, plus all 21 bundled OCR model assets.
- Release SHA-256: `78582e628da11187c26b97185e79d6d17557b36fb83548e156a4feb18209113a`.

## Network limitation and remaining checks

The ordinary `flutter build apk --debug` command reached native compilation and identified the Kotlin version requirement, which is fixed in the committed toolchain. Subsequent full builds stopped at dependency resolution for Android lint/annotation tooling such as `lint-gradle:31.13.2`: the environment proxy returned HTTP 503 transport errors. Independent requests to GitHub, npm, pub.dev, and Google's repository also failed with HTTP 503, confirming a broader outbound networking failure. Full annotation/lint tooling checks have not passed on this machine.

Once outbound networking is restored, rerun the unmodified standard workflow:

```sh
flutter pub get --enforce-lockfile
flutter build apk --debug
flutter build apk --release
```

Real-device camera/gallery OCR and Firebase account/device syncing are not yet verified. Run the two-device acceptance checks in README.md. The Firebase Console's Email/Password provider and production rules deployment were not modified by this task. Release signing uses a debug keystore **for release testing only**.

iOS compilation and code signing require macOS/Xcode and were not run on this Linux machine. The native project, deployment target, permissions, plist resource reference, and exact Firebase bundle ID are included.

## Cloud-only toolchain preparation

The initial SDK host returned HTTP 403, so the current machine obtained Flutter's SDK cache from Cirrus Labs' published Flutter 3.35.7 container, verifying each OCI layer's SHA-256 digest. Flutter Maven packaging was reconstructed locally from those verified SDK class/native-library bytes using Flutter's own pinned engine POM generator; byte hashes are recorded outside the checkout at `/workspace/flutter-maven-cache/provenance.json`. Downloads retained TLS and available artifact verification; the cached class/native-library bytes were unchanged. The Android project and GitHub Actions workflow use normal Flutter repositories by default; the local cache override lives only in `/workspace/flutter-env.sh`.

For this prepared cloud machine, source `/workspace/flutter-env.sh` before Flutter commands. `/workspace/run-bashahisab-rules.sh` starts the retained official Google Cloud Firestore emulator, runs the rules tests, and stops its own process. The emulator was obtained from Google's published Cloud CLI emulator container with OCI layer digest verification. A fresh startup and test run passed.
