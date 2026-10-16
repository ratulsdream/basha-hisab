import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/features/auth/auth_service.dart';
import 'package:basha_hisab/features/groups/group_selection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecoveryAuth extends MockFirebaseAuth {
  _RecoveryAuth()
    : super(
        mockUser: MockUser(uid: 'existing', email: 'alice@example.com'),
      );
  int signsIn = 0;
  String? normalizedEmail;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    throw FirebaseAuthException(code: 'email-already-in-use');
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    signsIn++;
    normalizedEmail = email;
    return super.signInWithEmailAndPassword(email: email, password: password);
  }
}

class _SlowAuth extends MockFirebaseAuth {
  final ready = Completer<void>();
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    await ready.future;
    return super.signInWithEmailAndPassword(email: email, password: password);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'registration recovers an Auth account whose earlier profile creation failed',
    () async {
      final auth = _RecoveryAuth();
      await AccountService(auth).register(' Alice@Example.COM ', 'password');
      expect(auth.signsIn, 1);
      expect(auth.normalizedEmail, 'alice@example.com');
      expect(auth.currentUser?.uid, 'existing');
    },
  );
  test('pending native Auth request prevents concurrent submissions', () async {
    final auth = _SlowAuth();
    final guarded = AccountService(auth);
    final first = guarded.signIn('a@example.com', 'password');
    expect(() => guarded.signIn('a@example.com', 'password'), throwsStateError);
    auth.ready.complete();
    await first;
    await guarded.signIn('a@example.com', 'password');
  });
  test('only transient completed network errors receive one retry', () async {
    var attempts = 0;
    final result = await authRequest(() async {
      attempts++;
      if (attempts == 1) {
        throw FirebaseAuthException(code: 'network-request-failed');
      }
      return 'ok';
    });
    expect(result, 'ok');
    expect(attempts, 2);
    attempts = 0;
    await expectLater(
      authRequest(() async {
        attempts++;
        throw FirebaseAuthException(code: 'wrong-password');
      }),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(attempts, 1);
  });
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late HouseholdRepository repository;
  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'alice',
        email: 'alice@example.com',
        displayName: 'Alice',
      ),
      signedIn: true,
    );
    repository = HouseholdRepository(firestore: db, auth: auth);
  });
  test(
    'profile recovery after Auth-only registration is safe and idempotent',
    () async {
      await repository.ensureProfile();
      final created = (await db.doc('users/alice').get()).data()!['createdAt'];
      await repository.updateProfile('Alice Smith');
      await repository.ensureProfile();
      final data = (await db.doc('users/alice').get()).data()!;
      expect(data['uid'], 'alice');
      expect(data['email'], 'alice@example.com');
      expect(data['displayName'], 'Alice Smith');
      expect(data['createdAt'], created);
      expect(data.containsKey('householdId'), false);
    },
  );
  test(
    'legacy migration preserves expenses, retries, and never resurrects a left group',
    () async {
      await db.doc('users/alice').set({
        'householdId': 'old',
        'name': 'Original',
        'inviteCode': 'a' * 32,
      });
      await db.doc('households/old').set({
        'memberIds': ['alice', 'bob'],
        'memberNames': {'alice': 'Original', 'bob': 'Bob'},
        'currency': 'EUR',
        'inviteCode': 'a' * 32,
      });
      await db.doc('households/old/expenses/existing').set({'total': 1234});
      await repository.ensureProfile();
      await repository.ensureProfile();
      expect((await db.collection('users/alice/memberships').get()).size, 1);
      expect((await db.doc('households/old/members/alice').get()).exists, true);
      expect((await db.doc('households/old/expenses/existing').get()).data(), {
        'total': 1234,
      });
      await repository.leaveGroup('old');
      await repository.ensureProfile();
      expect((await db.doc('users/alice/memberships/old').get()).exists, false);
      expect((await db.doc('users/alice').get()).exists, true);
    },
  );
  test(
    'create two homes, switch and leave without changing personal account',
    () async {
      await repository.ensureProfile();
      final first = await repository.createHousehold('First', 'EUR');
      final second = await repository.createHousehold('Second', 'EUR');
      expect((await db.collection('users/alice/memberships').get()).size, 2);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final selection = GroupSelection(prefs, 'alice');
      await selection.select(first);
      expect(selection.resolve([first, second]), first);
      await selection.select(second);
      expect(GroupSelection(prefs, 'alice').selected, second);
      expect(GroupSelection(prefs, 'bob').selected, isNull);
      await repository.leaveGroup(second);
      expect(selection.resolve([first]), isNull);
      expect(
        (await db.doc('users/alice').get()).data()!['displayName'],
        'Alice',
      );
      expect((await db.doc('households/$second').get()).exists, true);
    },
  );
  test('join another group while retaining an existing membership', () async {
    await repository.ensureProfile();
    await repository.createHousehold('First', 'EUR');
    await db.doc('invites/${'b' * 32}').set({'householdId': 'other'});
    await db.doc('households/other').set({
      'memberIds': ['bob'],
      'memberNames': {'bob': 'Bob'},
    });
    await repository.joinHousehold('  ${'B' * 32}  ');
    await repository.joinHousehold('b' * 32);
    expect((await db.collection('users/alice/memberships').get()).size, 2);
    expect((await db.doc('households/other').get()).data()!['memberIds'], [
      'bob',
      'alice',
    ]);
  });
  test('email normalization', () {
    expect(normalizeEmail('  Alice@Example.COM  '), 'alice@example.com');
  });
  test('timestamps retained in profile model', () {
    final time = Timestamp.fromDate(DateTime(2026));
    final profile = PersonalProfile.fromMap({
      'uid': 'a',
      'email': 'a@example.com',
      'displayName': 'A',
      'createdAt': time,
      'updatedAt': time,
    });
    expect(profile.createdAt, DateTime(2026));
  });
}
