import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/features/sync/outbox_store.dart';
import 'package:basha_hisab/features/sync/outbox_service.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late OutboxStore store;
  late HouseholdRepository repository;
  QueuedExpense draft([String id = 'stable']) => QueuedExpense({
    'owner': 'a',
    'id': id,
    'groupId': 'home',
    'total': 1250,
    'items': [],
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('outbox-test-');
    store = await OutboxStore.open(
      'a',
      path: '${temp.path}/drafts.db',
      factory: databaseFactoryFfi,
    );
    repository = HouseholdRepository(
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'a'), signedIn: true),
    );
  });
  tearDown(() async {
    await store.close();
    await temp.delete(recursive: true);
  });
  test(
    'disk restart recovers syncing draft with original identity and attempts',
    () async {
      await store.enqueue(draft());
      await store.mark('stable', 'syncing', '', attempted: true);
      final path = store.path;
      await store.close();
      store = await OutboxStore.open(
        'a',
        path: path,
        factory: databaseFactoryFfi,
      );
      final row = (await store.read()).single;
      expect(row.id, 'stable');
      expect(row.state, 'pending');
      expect(row.attempts, 1);
    },
  );
  test(
    'same ID is idempotent; changed payload and different owner are rejected',
    () async {
      await store.enqueue(draft());
      await store.enqueue(draft());
      expect((await store.read()).length, 1);
      await expectLater(
        store.enqueue(QueuedExpense({...draft().payload, 'total': 1500})),
        throwsStateError,
      );
      await expectLater(
        store.enqueue(QueuedExpense({...draft().payload, 'owner': 'b'})),
        throwsStateError,
      );
    },
  );
  test(
    'lost server acknowledgement retries original ID once; explicit review pauses',
    () async {
      await store.enqueue(draft());
      final accepted = <String>{};
      var attempts = 0;
      Future<void> sender(QueuedExpense row) async {
        accepted.add(row.id);
        attempts++;
        if (attempts == 1) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          );
        }
      }

      await OutboxService(store, repository, sender: sender).drain();
      expect((await store.read()).single.state, 'pending');
      await OutboxService(store, repository, sender: sender).drain();
      expect(accepted, {'stable'});
      expect(await store.read(), isEmpty);
      await store.enqueue(draft('duplicate'));
      await OutboxService(
        store,
        repository,
        sender: (_) => throw const DraftNeedsReview('Possible duplicate'),
      ).drain();
      expect((await store.read()).single.state, 'attention');
      await OutboxService(
        store,
        repository,
        sender: (_) => fail('must not upload without review'),
      ).drain();
    },
  );
  test('sign out never drains old account drafts', () async {
    await store.enqueue(draft());
    await repository.auth.signOut();
    await OutboxService(
      store,
      repository,
      sender: (_) => fail('signed out'),
    ).drain();
    expect((await store.read()).single.attempts, 0);
  });
  test('stale membership pauses before any financial write', () async {
    await repository.db.doc('households/home').set({
      'memberIds': ['a', 'c'],
      'memberNames': {'a': 'A', 'c': 'C'},
      'currency': 'EUR',
      'inviteCode': 'x',
    });
    await store.enqueue(
      QueuedExpense({
        ...draft().payload,
        'members': ['a', 'b'],
        'payer': 'a',
      }),
    );
    await OutboxService(store, repository).drain();
    expect((await store.read()).single.state, 'attention');
    expect(
      (await repository.db.collection('households/home/expenses').get()).docs,
      isEmpty,
    );
  });
  test(
    'concurrent drains share one worker and acknowledgement removes draft',
    () async {
      await store.enqueue(draft());
      var sends = 0;
      Future<void> sender(QueuedExpense _) async {
        sends++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      await Future.wait([
        OutboxService(store, repository, sender: sender).drain(),
        OutboxService(store, repository, sender: sender).drain(),
      ]);
      expect(sends, 1);
      expect(await store.read(), isEmpty);
    },
  );
}
