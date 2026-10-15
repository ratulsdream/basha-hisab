import 'package:flutter_test/flutter_test.dart';
import 'package:basha_hisab/domain.dart';

void main() {
  group('money parsing', () {
    test('uses integer cents and validates input', () {
      expect(parseMoney('1,234.56'), 123456);
      expect(parseMoney('0.1'), 10);
      expect(parseMoney('100'), 10000);
      expect(parseMoney('0'), 0);
      for (final invalid in [
        '-1',
        'NaN',
        '1.234',
        '',
        '10000000.01',
        '1e3',
        '1,2.50',
        '1.2.3',
      ]) {
        expect(parseMoney(invalid), isNull, reason: invalid);
      }
    });
  });
  group('monthly 50/50 settlement', () {
    test('finds who owes whom based on paid amount less share', () {
      final result = calculateSettlement(
        ['a', 'b'],
        [(payer: 'a', amount: 10000), (payer: 'b', amount: 4000)],
      );
      expect(result.total, 14000);
      expect(result.shares, {'a': 7000, 'b': 7000});
      expect(result.debtor, 'b');
      expect(result.creditor, 'a');
      expect(result.amount, 3000);
    });
    test('settlement reverses when the other person paid more', () {
      final result = calculateSettlement(
        ['a', 'b'],
        [(payer: 'b', amount: 5000)],
      );
      expect(result.debtor, 'a');
      expect(result.creditor, 'b');
      expect(result.amount, 2500);
    });
    test('odd cents are deterministic regardless of membership ordering', () {
      final result = calculateSettlement(
        ['b', 'a'],
        [(payer: 'a', amount: 101)],
      );
      expect(result.shares, {'a': 51, 'b': 50});
      expect(result.amount, 50);
      expect(result.shares.values.reduce((a, b) => a + b), result.total);
    });
    test('zero and equal spending have no debt', () {
      expect(calculateSettlement(['a', 'b'], []).amount, 0);
      final result = calculateSettlement(
        ['a', 'b'],
        [(payer: 'a', amount: 200), (payer: 'b', amount: 200)],
      );
      expect(result.amount, 0);
      expect(result.debtor, isNull);
    });
    test('one member has a reserved half without a fabricated debt', () {
      final result = calculateSettlement(['a'], [(payer: 'a', amount: 200)]);
      expect(result.shares['a'], 100);
      expect(result.debtor, isNull);
    });
    test('rejects invalid membership and expenses', () {
      expect(
        () => calculateSettlement(['a', 'b', 'c'], []),
        throwsArgumentError,
      );
      expect(
        () => calculateSettlement(['a', 'b'], [(payer: 'c', amount: 1)]),
        throwsArgumentError,
      );
    });
  });
  group('receipt parser', () {
    test('detects merchant, date, item prices and grand total', () {
      final receipt = parseReceipt(
        'Fresh Market\n2026-10-15\nMilk 120.50\nRice 200.00\nSubtotal 320.50\nVAT 10.00\nGrand Total 330.50\nCash 400.00\nChange 69.50',
      );
      expect(receipt.merchant, 'Fresh Market');
      expect(receipt.date, DateTime(2026, 10, 15));
      expect(receipt.total, 33050);
      expect(receipt.items.map((i) => i.name), ['Milk', 'Rice']);
      expect(receipt.items.map((i) => i.amount), [12050, 20000]);
    });
    test('never silently invents a total or normalizes an invalid date', () {
      final receipt = parseReceipt('Shop\n31/02/2026\nApple 2.00');
      expect(receipt.total, isNull);
      expect(receipt.date, isNull);
    });
    test('empty and unreadable receipts are editable blank drafts', () {
      final receipt = parseReceipt('');
      expect(receipt.merchant, '');
      expect(receipt.items, isEmpty);
      expect(receipt.total, isNull);
    });
    test('parses day first and thousands separators', () {
      final receipt = parseReceipt(
        'Store\n15/10/2026\nRice 1,200.00\nTOTAL 1,200.00',
      );
      expect(receipt.date, DateTime(2026, 10, 15));
      expect(receipt.total, 120000);
    });
  });
  test(
    'month keys are padded',
    () => expect(monthKey(DateTime(2026, 2)), '2026-02'),
  );
  test('invitation codes carry 128 bits and are unique', () {
    final codes = List.generate(100, (_) => newInviteCode());
    expect(codes.toSet().length, 100);
    expect(
      codes.every((code) => RegExp(r'^[a-f0-9]{32}$').hasMatch(code)),
      isTrue,
    );
  });
}
