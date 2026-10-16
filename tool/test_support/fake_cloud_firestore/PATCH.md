Test-only copy of fake_cloud_firestore 4.1.1 (MIT). One upstream 4.3.0 fix is
backported: WriteBatch.update<T>(DocumentReference<T>, T) matches Firestore 6.10.
Upstream 4.2+ requires meta 1.17 via rx, incompatible with Flutter 3.35.7's
meta 1.16 pin. Remove this copy when upgrading the Flutter SDK. Production APKs
do not include this dev dependency. Security tests use the real emulator.
