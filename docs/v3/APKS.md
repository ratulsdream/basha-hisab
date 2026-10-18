# Verified Android test builds

Latest: **BashaHisab 3.1 Simple Dashboard** — [download the APK artifact](https://github.com/ratulsdream/basha-hisab/actions/runs/39118754893/artifacts/12133701116).

Sign in to GitHub, tap **BashaHisab-v3.1-dashboard-debug**, extract the downloaded
ZIP in Android Files/Downloads, then tap **BashaHisab-v3.1-dashboard-debug.apk**.
The artifact contains the already-built APK and its BUILD-INFO.json manifest.
Source: `d105ba11e950975472d0b21e486efda885005d35`.
SHA-256: `0215d84668e7454226a5ae9da81fc6f5b21e750cb915d9090f939ecc567994f3`.
Android ID com.bashahisab.app; version 3.1.0-dashboard+8; debug signature verified.

87 Flutter tests passed with flags off and on, 33 security emulator tests passed,
and the real FlutterFire/Auth/Firestore emulator integration passed in the
linked delivery run. Greek/English native OCR fixtures also passed. The real SDK
integration is not a physical Android/iOS test or production-rule verification.
Normal builds keep v3 modules locked pending that verification and explicit
approval. Read [3.1 installation/migration notes](DASHBOARD_RELEASE.md) and
[how to provide published rules](SECURITY_REVIEW_3_1.md) before enabling anything.

Earlier phase builds follow for reference.


All are debug-signed Android universal APKs. Standard builds keep new v3 modules
closed until the production security audit; do not mistake installation for a
verified production rollout. Existing accounts, source expenses and groups are
preserved. [Read migration and blockers before installing](PHASE_3.md).

| Phase | Source commit | Download artifact |
|---|---|---|
| 0 | 22d735f | [Phase 0](https://github.com/ratulsdream/basha-hisab/actions/runs/39072345982/artifacts/12115448764) |
| 1 | 883f176 | [Phase 1](https://github.com/ratulsdream/basha-hisab/actions/runs/39073293263/artifacts/12116400641) |
| 2 | 9b66888 | [Phase 2](https://github.com/ratulsdream/basha-hisab/actions/runs/39074162146/artifacts/12116441766) |
| 3 (latest) | 398bf28 | [Phase 3](https://github.com/ratulsdream/basha-hisab/actions/runs/39075199874/artifacts/12116936956) |

GitHub sign-in is required to download Actions artifacts. Tap the artifact,
extract the ZIP using Android Files/Downloads, then tap the enclosed
`BashaHisab-v3-phase-3-debug.apk`. The workflow retains artifacts for 30 days.
Artifacts were assembled from already-built APKs and verified against source
commit/size/SHA-256 manifests; no rebuild is performed by the delivery workflow.

Phase 3: package com.bashahisab.app, version 3.0.0-phase.3, versionCode 7.
SHA-256: `d65136907020454f37aa584ec8d1d8b51b28bdd3a75ed88a5facc90bfea29e95`.
Both bundled ell/eng OCR models and the local Greek PDF font were checked in
the APK; Android APK signature verification passed. No iOS build is claimed.
