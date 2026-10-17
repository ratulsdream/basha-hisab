/// Fail closed until the issue #1 Phase 0 deployed-rules audit is completed.
/// Enable only for a verified rules deployment or an isolated emulator build.
const v3ItemsEnabled = bool.fromEnvironment(
  'V3_ITEMS_ENABLED',
  defaultValue: false,
);
