import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/features/planning/planning_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'repayments settle one month and cannot carry into the next month',
    (tester) async {
      final db = FakeFirebaseFirestore(), now = DateTime.now();
      final month = DateTime(now.year, now.month),
          next = DateTime(now.year, now.month + 1);
      for (final date in [month, next]) {
        await db.doc('households/home/expenses/e${date.month}').set({
          'merchant': 'Market',
          'payer': 'a',
          'createdBy': 'a',
          'date': Timestamp.fromDate(date),
          'month': '${date.year}-${date.month.toString().padLeft(2, '0')}',
          'total': 1000,
          'itemCount': 0,
        });
      }
      await db.doc('households/home/payments/p').set({
        'from': 'b',
        'to': 'a',
        'amount': 500,
        'date': Timestamp.fromDate(month),
        'month': '${month.year}-${month.month.toString().padLeft(2, '0')}',
        'reversalOf': '',
        'reference': '',
      });
      final repository = HouseholdRepository(
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
      await tester.pumpWidget(
        MaterialApp(
          home: PlanningScreen(repository: repository, household: home),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repayments'));
      await tester.pumpAndSettle();
      expect(find.text('No remaining recorded dues.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.textContaining('B owes A EUR 5.00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
