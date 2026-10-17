import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'lost save acknowledgement retries idempotently and rejects conflicting payload',
    () async {
      final db = FakeFirebaseFirestore();
      final repository = HouseholdRepository(
        firestore: db,
        auth: MockFirebaseAuth(mockUser: MockUser(uid: 'a'), signedIn: true),
      );
      final home = Household('home', {
        'memberIds': ['a', 'b'],
        'memberNames': {'a': 'A', 'b': 'B'},
        'currency': 'EUR',
        'inviteCode': 'a' * 32,
      });
      Future<void> save(String name) => repository.saveExpense(
        household: home,
        id: 'stable',
        merchant: 'Market',
        payer: 'a',
        date: DateTime(2026, 10, 17),
        items: [ExpenseItem(name, 250)],
        total: 250,
      );
      await save('Milk');
      await save('Milk');
      expect((await db.collection('households/home/expenses').get()).size, 1);
      expect(
        (await db.collection('households/home/expenses/stable/items').get())
            .size,
        1,
      );
      await expectLater(save('Rice'), throwsStateError);
      expect(
        (await db.doc('households/home/expenses/stable/items/0').get())
            .data()!['name'],
        'Milk',
      );
    },
  );
}
