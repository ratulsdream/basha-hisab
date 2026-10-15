import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/domain.dart';
import 'package:basha_hisab/screens.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _UnusedAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _RecordingRepository extends HouseholdRepository {
  _RecordingRepository()
    : super(firestore: _UnusedFirestore(), auth: _UnusedAuth());
  int saves = 0;
  String? savedMerchant;
  int? savedTotal;
  List<ExpenseItem>? savedItems;
  @override
  String get uid => 'alice';
  @override
  String newExpenseId(String household) => 'test-expense';
  @override
  Future<void> saveExpense({
    required Household household,
    required String id,
    required String merchant,
    required String payer,
    required DateTime date,
    required List<ExpenseItem> items,
    required int total,
  }) async {
    saves++;
    savedMerchant = merchant;
    savedTotal = total;
    savedItems = items;
  }
}

void main() {
  final household = Household('home', {
    'memberIds': ['alice', 'bob'],
    'memberNames': {'alice': 'Alice', 'bob': 'Bob'},
    'currency': 'BDT',
    'inviteCode': '0123456789abcdef0123456789abcdef',
  });
  testWidgets(
    'OCR always requires explicit review and saves edited structured data',
    (tester) async {
      final repository = _RecordingRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseEditor(
            repository: repository,
            household: household,
            draft: ReceiptDraft(
              merchant: 'Wrong OCR name',
              total: 250,
              date: DateTime(2026, 10, 15),
            ),
            fromReceipt: true,
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'Corrected shop',
      );
      final save = find.text('Save expense');
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.saves, 0);
      expect(
        find.text(
          'Review the receipt fields and confirm the checkbox before saving.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.saves, 1);
      expect(repository.savedMerchant, 'Corrected shop');
      expect(repository.savedTotal, 250);
      expect(repository.savedItems, isEmpty);
    },
  );
  testWidgets('manual expense refuses a missing merchant and zero total', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseEditor(
          repository: repository,
          household: household,
          draft: const ReceiptDraft(total: 0),
          fromReceipt: false,
        ),
      ),
    );
    final save = find.text('Save expense');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    expect(
      find.text('Enter a total greater than zero (up to 10,000,000).'),
      findsOneWidget,
    );
  });
  testWidgets('an offscreen empty merchant cannot bypass validation', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseEditor(
          repository: repository,
          household: household,
          draft: const ReceiptDraft(total: 250),
          fromReceipt: false,
        ),
      ),
    );
    final save = find.text('Save expense');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    expect(
      find.text('Enter a merchant or expense name (up to 100 characters).'),
      findsOneWidget,
    );
  });
  testWidgets('item and receipt total mismatch needs a second confirmation', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseEditor(
          repository: repository,
          household: household,
          draft: const ReceiptDraft(
            merchant: 'Shop',
            total: 300,
            items: [ExpenseItem('Milk', 250)],
          ),
          fromReceipt: true,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    final save = find.text('Save expense');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Items and total differ'), findsOneWidget);
    expect(repository.saves, 0);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save this total'));
    await tester.pumpAndSettle();
    expect(repository.saves, 1);
    expect(repository.savedTotal, 300);
    expect(repository.savedItems!.single.amount, 250);
  });
}
