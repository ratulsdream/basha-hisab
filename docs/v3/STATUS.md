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

Remaining work proceeds in issue order:

- Phase 3 (15–18): notification preferences and local/background configuration,
  PDF/Excel export, durable offline queue/synchronization, profile/group polish.

Production security audit, production rollout, APNs/Apple setup and physical
device acceptance are separate from repository implementation. No APK should be
represented as production-verified while those checks remain unresolved.
