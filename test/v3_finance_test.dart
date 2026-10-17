import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/domain.dart';
import 'package:basha_hisab/features/planning/planning_domain.dart';
import 'package:basha_hisab/features/planning/planning_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceEntry entry(
  String id,
  int amount, {
  String payer = 'a',
  bool refund = false,
  bool personal = false,
  bool voided = false,
  Map<String, int>? splits,
}) => FinanceEntry(
  id: id,
  merchant: 'Market',
  payer: payer,
  date: DateTime(2026, 10, 17),
  amount: amount,
  refund: refund,
  personal: personal,
  voided: voided,
  splits: splits,
);
void main() {
  test(
    'custom percentage allocation conserves exact cents including 60/40 and 100/0',
    () {
      expect(percentageSplit(101, {'a': 6000, 'b': 4000}), {'a': 61, 'b': 40});
      expect(percentageSplit(101, {'a': 10000, 'b': 0}), {'a': 101, 'b': 0});
      for (var total = 1; total < 1000; total++) {
        expect(
          percentageSplit(total, {
            'a': 3333,
            'b': 6667,
          }).values.reduce((a, b) => a + b),
          total,
        );
      }
      expect(
        () => percentageSplit(100, {'a': -1, 'b': 10001}),
        throwsArgumentError,
      );
      expect(() => fixedSplit(100, {'a': 60, 'b': 39}), throwsArgumentError);
    },
  );
  test(
    'refunds reduce paid/share amounts, private and voided costs never enter group split',
    () {
      final s = financeSettlement(['a', 'b'], ['a', 'b'], [
        entry('spend', 1000),
        entry('refund', 200, refund: true),
        entry('private', 99999, personal: true),
        entry('void', 99999, voided: true),
      ], []);
      expect(s.total, 800);
      expect(s.shares, {'a': 400, 'b': 400});
      expect(s.transfers.single.amount, 400);
    },
  );
  test('partial/full repayment and reversal change dues, never spending', () {
    final p = Repayment(
      id: 'p',
      from: 'b',
      to: 'a',
      amount: 300,
      date: DateTime(2026, 10, 17),
    );
    final costs = [entry('e', 1000)];
    final partial = financeSettlement(['a', 'b'], ['a', 'b'], costs, [p, p]);
    expect(partial.total, 1000);
    expect(partial.transfers.single.amount, 200);
    final reversed = financeSettlement(['a', 'b'], ['a', 'b'], costs, [
      p,
      Repayment(
        id: 'reverse_p',
        from: 'b',
        to: 'a',
        amount: 300,
        date: p.date,
        reversalOf: 'p',
      ),
    ]);
    expect(reversed.transfers.single.amount, 500);
  });
  test('custom fixed cents and default monthly rounding stay exact', () {
    final s = financeSettlement(['a', 'b'], ['a', 'b'], [
      entry('custom', 101, splits: {'a': 80, 'b': 21}),
      entry('equal1', 101),
      entry('equal2', 101),
    ], []);
    expect(s.shares, {'a': 181, 'b': 122});
    expect(s.total, 303);
    expect(s.transfers.single.amount, 122);
  });
  test(
    'recurring dates clamp to month end; each month has one stable occurrence id',
    () {
      expect(recurringDate(DateTime(2026, 2), 31), DateTime(2026, 2, 28));
      expect(
        occurrenceId('rent', DateTime(2026, 2)),
        occurrenceId('rent', DateTime(2026, 2, 20)),
      );
      expect(
        occurrenceId('rent', DateTime(2026, 2)),
        isNot(occurrenceId('rent', DateTime(2026, 3))),
      );
    },
  );
  test(
    'personal saves never write group expenses or shared item library',
    () async {
      final db = FakeFirebaseFirestore();
      final r = HouseholdRepository(
        firestore: db,
        auth: MockFirebaseAuth(mockUser: MockUser(uid: 'a'), signedIn: true),
        enableItemIntelligence: true,
      );
      final home = Household('home', {
        'memberIds': ['a', 'b'],
        'memberNames': {'a': 'A', 'b': 'B'},
        'currency': 'EUR',
        'inviteCode': 'a' * 32,
      });
      await r.savePlannedExpense(
        household: home,
        id: 'private',
        merchant: 'Pharmacy',
        payer: 'a',
        date: DateTime(2026, 10, 17),
        items: const [ExpenseItem('Personal', 200)],
        total: 200,
        personal: true,
      );
      expect((await db.collection('users/a/personalExpenses').get()).size, 1);
      expect((await db.collection('households/home/expenses').get()).size, 0);
      expect((await db.collection('households/home/purchases').get()).size, 0);
    },
  );
  test('payment retries are idempotent; conflicting bodies fail', () async {
    final db = FakeFirebaseFirestore(),
        r = PlanningRepository(FakeFirebaseFirestore(), 'a', 'home');
    final repo = PlanningRepository(db, 'a', 'home');
    Future<void> pay(int amount) => repo.recordPayment(
      id: 'stable',
      from: 'b',
      to: 'a',
      amount: amount,
      date: DateTime(2026, 10, 17),
    );
    await pay(100);
    await pay(100);
    expect((await repo.collection('payments').get()).size, 1);
    await expectLater(pay(200), throwsStateError);
    expect(r.groupId, 'home');
  });
}
