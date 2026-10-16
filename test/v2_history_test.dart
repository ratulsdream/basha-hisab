import 'package:basha_hisab/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v2 preserves v1 monthly odd-cent rounding for the same pair', () {
    final result = calculateGroupSettlement(['a', 'b'], ['a', 'b'], [
      (payer: 'a', amount: 101, splitBetween: null),
      (payer: 'a', amount: 101, splitBetween: ['b', 'a']),
    ]);
    expect(result.shares, {'a': 101, 'b': 101});
    expect(result.transfers.single.amount, 101);
  });
  test('former roommate remains in historical 50/50 settlement', () {
    final result = calculateGroupSettlement(['bob'], ['alice', 'bob'], [
      (payer: 'alice', amount: 1000, splitBetween: null),
    ]);
    expect(result.total, 1000);
    expect(result.shares, {'bob': 500, 'alice': 500});
    expect(result.transfers.single, (
      debtor: 'bob',
      creditor: 'alice',
      amount: 500,
    ));
  });
  test('a replacement roommate does not inherit previous expenses', () {
    final result = calculateGroupSettlement(
      ['bob', 'charlie'],
      ['alice', 'bob'],
      [
        (payer: 'alice', amount: 1000, splitBetween: null),
        (payer: 'charlie', amount: 600, splitBetween: ['bob', 'charlie']),
      ],
    );
    expect(result.shares, {'bob': 800, 'charlie': 300, 'alice': 500});
    expect(result.paid, {'bob': 0, 'charlie': 600, 'alice': 1000});
    expect(result.transfers.map((t) => t.amount).reduce((a, b) => a + b), 800);
  });
  test('odd cent is allocated deterministically for each purchase', () {
    final result = calculateGroupSettlement(['a', 'b'], ['a', 'b'], [
      (payer: 'a', amount: 101, splitBetween: ['b', 'a']),
    ]);
    expect(result.shares, {'a': 51, 'b': 50});
    expect(result.transfers.single.amount, 50);
  });
}
