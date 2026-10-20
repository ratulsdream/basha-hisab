# Exact rules deployment approved; execution and verification pending

The owner explicitly approved the following production change in this chat,
after reviewing DEPLOYED_RULES_COMPARISON.md:

- Project: `bashahisab-a6dd6`, default Firestore database only.
- Candidate SHA-256: `c0ece12ebca45c856fb3d053be07ab10a96be3ce6389cbae7dc035167e35d579`.
- Before changing anything, require the live policy to match the reviewed export
  (`8f92d9c6e9fdb9ff292ec3e803b266e7e87859f0d2e1deb15ae99052eb053a7d`).
  Stop and ask the owner if it changed. Preserve the original rules backup.
- Change only Firestore security rules. No indexes, Functions, Storage or documents.
- Re-export and verify the published source. Only then test/build the Android app
  with both `V3_ENABLED=true` and `V3_ITEMS_ENABLED=true` and provide a download.

Approval is not evidence that the deployment ran. No deployment was executed
from the development environment, which has no administrative Firebase sign-in.
The owner must run the helper in their already authenticated Google Cloud Shell.
Do not ask for passwords, authorization codes, service-account keys or tokens.

## Guarded helper

`tool/security/deploy_approved_rules.py` is specific to this approval. Its default
mode is read-only preflight. Publication additionally requires
`--deploy-approved-sha256` equal to the exact approved hash. Its source download
is pinned to commit `7c6ffd859c2cf8a1592d832d1eb5bb67cbb76470`, then hashed before
any authenticated operation. Project, source hash, baseline hash, ruleset identity
and release timestamp cannot be changed by command-line arguments.

It uses the official Firebase Rules API with the existing Cloud Shell `gcloud`
sign-in, instead of the generic Firebase deployment command proposed in the
initial plan. This keeps the executable's mutation scope to two Rules API
operations and avoids any dependence on local Firebase project configuration,
index configuration, CLI login or deployment hooks. The installed Firebase CLI
uses the same ruleset creation and release publication API mechanism.

The only allowed authenticated operations are:

1. GET this project's exact `cloud.firestore` release and individual rulesets.
2. POST one immutable ruleset containing only `firestore.rules` with the approved
   content. Read it back and verify its hash before publication.
3. PATCH this project's exact `cloud.firestore` release, with update mask
   `rulesetName`, pointing to that newly created ruleset.

The helper saves exclusive `before.rules` and `before.metadata.json` backups,
re-exports the baseline immediately before the PATCH, then exports and verifies
the published source and ruleset identity. It checks release stability during
each export. Authorization headers are kept in memory and redirects are rejected.
No credential is included in the generated ZIP.

The API provides no atomic compare-and-swap/etag for release updates. Keep Firebase
Console publishing and other rules deployments idle during this short operation.
The helper checks immediately before publication and again afterward; it cannot
eliminate an intervening concurrent publisher at the API level.

## Evidence and failure handling

Use a new persistent directory under the Cloud Shell home directory for each
attempt. Keep the original `BashaHisab-rules-review.zip` too. Never overwrite an
earlier evidence directory or backup.

The generated `BashaHisab-deployment-verification.zip` contains only known rules
snapshots, version metadata and `result.json`. Upload that ZIP for review before
building a production-enabled APK. A successful result must say `VERIFIED`, name
the approved project, contain the exact baseline source/hash, and contain the
exact approved published source/hash with the new release identity.

On a changed baseline, the helper stops before publication. If the second check
fails after staging, an unpublished ruleset may remain; it does not change live
access. No automatic deletion, rollback or write retry is performed.

An interrupted PATCH response is ambiguous: the helper performs read-only
verification. It reports `VERIFIED` only if the new ruleset identity and approved
source are actually live and stable. Otherwise it reports `STOPPED`. Send the
evidence ZIP and do not rerun a deployment blindly. Any new or changed policy
requires comparison before further mutation.

## Next application stage after verified publication

Validation of the deployment helper: all 29 Python security-helper tests pass,
including 23 deployment tests with synthetic sources and mocked credentials/API
responses. Tests cover changed baselines, read-only defaults, exact request scope,
staged and published hash checks, backup preservation, malformed/interrupted
responses, no mutation retries, and exclusion of credentials from evidence.
This is helper validation, not evidence of a production deployment.

Run Flutter analysis, enabled Flutter tests, security tests and the appropriate
repository integration checks; build with both approved flags true. Preserve the
Android application ID, signing compatibility, existing Firebase configuration,
iOS bundle ID and on-device OCR. No new data migration or production test-record
insertion is part of this rules deployment. Device acceptance and optional remote
notification/APNs configuration must be reported separately from emulator checks.

Normal production gates remain false until evidence of publication is received
and checked. Previously downloaded APKs retain their old compile-time flags.
