Optional notification backend; no deployment is authorized or configured.

Run `node --test notifications.test.cjs` for the pure delivery policy tests.
After separately reviewed production rules, owner Firebase/billing approval and
APNs setup, an administrator can install dependencies and add an explicit
Functions deployment configuration. Set BASHAHISAB_NOTIFICATIONS_ENABLED=true
only for that reviewed environment. Default does nothing. Do not deploy these
Functions against production as part of APK setup.

Delivery reads current group membership, preferences and owner-private tokens.
It excludes the acting user for expense/shopping changes, uses generic data-only
pushes, claims one attempt per device/event, and leaves personal expenses alone.
Foreground client alerts use the same event key. A claim before an uncertain
send intentionally risks a missed advisory alert rather than duplicate pushes.
No scheduler, paid OCR or Storage is used. Recurring/monthly reminders are local.
The client must be built with V3_REMOTE_NOTIFICATIONS=true after server setup.
Review the pinned package-lock.json before deployment; the source here is optional and has not been live-deployed/tested.
