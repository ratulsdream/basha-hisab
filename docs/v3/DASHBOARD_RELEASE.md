# BashaHisab 3.1 — Simple Dashboard testing candidate

The four bottom destinations reuse the existing app, accounts and Firestore
paths. Home shows current-month spending, personal and roommate contributions,
shared share, settlement, budgets, recent expenses, regular items, pending
shopping and relevant local sync/draft state. History has its own month selector;
changing history never changes Home's current-month scope.

Items opens the existing library, regular purchases, shopping, kitchen and
price tools. History links to search, category reports, payments, private
spending and PDF/Excel. More contains profile, groups, invitation, budget,
recurring bills, notifications, language/appearance, settings and leave/sign-out.
Receipt camera/gallery → offline Greek/English OCR → explicit review → existing
save flow is retained. Photos remain local; no Storage or cloud OCR added.

Material 3 teal styling, rounded cards, readable metrics, flexible action rows,
light/dark/system appearance and local English/Bengali choices are included.
Noto Sans Bengali is bundled with its license; Greek receipt/item/merchant text
remains source data, never machine-translated. Preference changes do not touch
Firestore. Raw OCR and server-provided details retain their original language.

Unavailable modules show their feature list and an explanation of pending
access review. Existing history and quick receipt/manual actions remain usable.
No compilation flag was enabled for production and no rules were deployed.

## Installation / additive migration

Install the debug APK over the matching signed existing app; keep the same
Firebase project, Android com.bashahisab.app and iOS Com.bashahisab.app. Version
3.1.0-dashboard+8 adds local ui.language/ui.theme preferences and fonts, no data
rewrite. Existing account recovery and idempotent legacy membership migration
remain unchanged. Do not uninstall or clear storage with unsynced drafts.
The dashboard itself writes no expenses, shopping, stock, payment or migration
data simply by viewing it. Opening the app's existing account recovery still
uses its additive profile/membership flow.

Production activation is NOT complete. See SECURITY_REVIEW_3_1.md for the precise
rule export, review, approval and activation sequence. Never enable production
v3 modules solely to remove a locked-state message.


Validation: 87 Flutter tests passed in both default and V3_ENABLED=true builds;
33 Firestore emulator authorization tests, 6 audit/export helper tests and 2
notification policy tests passed. Flutter analyze and formatting/actionlint are
clean. The offline native Tesseract smoke test recognized Greek and English
fixture dates/totals. Android debug build and APK signature verification passed;
package version is 3.1.0-dashboard+8. Native camera/gallery, actual phone offline
reconnect and iOS compilation remain device/Mac acceptance, not claimed here.

Navigation follow-up preserves the chosen History month in reports, removes a
misleading nested back button from Items, and refreshes reminder scheduling after
notification settings change from More. Group switch tests confirm separate
home histories and per-account remembered group IDs without modifying expenses.


The locked dashboard interprets any existing refund/custom-split metadata from
already-readable shared expenses. It labels settlement as a shared-expense
balance until repayment access is verified, rather than implying those payment
records were read. The unavailable-planning History action opens real History.

The real FlutterFire/local-emulator integration passed in GitHub Actions:
https://github.com/ratulsdream/basha-hisab/actions/runs/39118754893
It exercised actual repositories and SDKs with V3_ENABLED=true, beyond fake
Firestore widget tests. This validates the candidate against local rules, not
the currently deployed production rules or physical-device behavior.
