# Issue #1 implementation tracker

Source: https://github.com/ratulsdream/basha-hisab/issues/1

Phase 0 repository safety baseline is committed as 22d735f. The deployed-rules
comparison is unresolved because no administrative read connection/export is
available. Owner explicitly instructed continuation of repository/emulator work,
without overwriting/deploying production rules or modifying production data.

Phase 1 implements features 1–7 as a gated candidate: library, regular items,
shopping, kitchen inventory, price history, duplicates, and improved OCR. See
PHASE_1.md for scope, migration and enablement boundary.

Phase 2 now implements features 8–14 as a gated candidate; see PHASE_2.md.

Phase 3 implements features 15–18 as a gated candidate; see PHASE_3.md for
notification configuration, export privacy and durable offline queue behavior.

All 18 issue features now have repository implementations. This is not a
production rollout completion: the deployed-rule comparison remains blocked,
and remote push/APNs and physical-device acceptance require owner environment
configuration/testing. Standard APKs keep v3 modules closed pending that audit.

Production security audit, production rollout, APNs/Apple setup and physical
device acceptance are separate from repository implementation. No APK should be
represented as production-verified while those checks remain unresolved.
