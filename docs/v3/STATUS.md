# Issue #1 implementation tracker

Source: https://github.com/ratulsdream/basha-hisab/issues/1

Phase 0 repository safety baseline is committed as 22d735f. On 2026-10-18 the
owner supplied an authenticated published-rules export. Comparison is complete:
published rules support the legacy app but deny the new v3 paths. The candidate
passes all 33 emulator tests; the published policy passes all 18 baseline cases
and denies the 15 v3 scenarios. See DEPLOYED_RULES_COMPARISON.md for exact hashes,
the proposed changes and the rules-only approval scope. Production deployment
and activation still require explicit owner approval and post-deployment export
verification. No production rules or data have been changed.

Phase 1 implements features 1–7 as a gated candidate: library, regular items,
shopping, kitchen inventory, price history, duplicates, and improved OCR. See
PHASE_1.md for scope, migration and enablement boundary.

Phase 2 now implements features 8–14 as a gated candidate; see PHASE_2.md.

Phase 3 implements features 15–18 as a gated candidate; see PHASE_3.md for
notification configuration, export privacy and durable offline queue behavior.

All 18 issue features now have repository implementations. This is not a
production rollout completion: approved deployment and activation remain pending,
and remote push/APNs and physical-device acceptance require owner environment
configuration/testing. Standard APKs keep v3 modules closed pending that audit.

Production security audit, production rollout, APNs/Apple setup and physical
device acceptance are separate from repository implementation. No APK should be
represented as production-verified while those checks remain unresolved.


3.1 redesign: four-tab dashboard/theme/language stage committed as 8ac632d.
Repository security audit extended with per-collection cross-group and leave
revocation matrices; the published rules have now been compared. Normal
build flags remain closed. See DASHBOARD_RELEASE.md and SECURITY_REVIEW_3_1.md.

3.1 final UI validation: 87 Flutter tests pass in both default and enabled
configurations, with 33 security emulator tests and a successful genuine
FlutterFire/Auth/Firestore emulator repository scenario in Actions. Production
rule comparison is complete; explicitly approved deployment/activation remain
pending. No production rules or data were changed.


Final 3.1 APK source: d105ba1. Download and exact manifest digest are in APKS.md.
Delivery run 39118754893 passed the real SDK integration and published the APK.
Production rules deployment/activation and physical-device/iOS acceptance remain
pending. The rules file is unchanged by 3.1 and by the export comparison.
