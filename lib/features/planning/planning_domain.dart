import 'dart:convert';
import '../../domain.dart';

const expenseCategories = [
  'uncategorized',
  'food',
  'rice',
  'vegetables',
  'household',
  'utilities',
  'other',
];

Map<String, int> percentageSplit(int total, Map<String, int> basisPoints) {
  if (total <= 0 ||
      basisPoints.isEmpty ||
      basisPoints.values.any((v) => v < 0) ||
      basisPoints.values.fold<int>(0, (acc, v) => acc + v) != 10000) {
    throw ArgumentError('Percentages must add to 100%.');
  }
  final allocated = {
    for (final uid in basisPoints.keys) uid: total * basisPoints[uid]! ~/ 10000,
  };
  final order = basisPoints.keys.toList()
    ..sort((a, b) {
      final diff =
          (total * basisPoints[b]! % 10000) - (total * basisPoints[a]! % 10000);
      return diff == 0 ? a.compareTo(b) : diff;
    });
  var remainder = total - allocated.values.fold<int>(0, (acc, v) => acc + v);
  for (final uid in order) {
    if (remainder == 0) break;
    allocated[uid] = allocated[uid]! + 1;
    remainder--;
  }
  return allocated;
}

Map<String, int> fixedSplit(int total, Map<String, int> cents) {
  if (cents.isEmpty ||
      cents.values.any((v) => v < 0) ||
      cents.values.fold<int>(0, (acc, v) => acc + v) != total) {
    throw ArgumentError('Fixed shares must add to the exact receipt total.');
  }
  return Map.of(cents);
}

class FinanceEntry {
  const FinanceEntry({
    required this.id,
    required this.merchant,
    required this.payer,
    required this.date,
    required this.amount,
    this.category = 'uncategorized',
    this.refund = false,
    this.voided = false,
    this.personal = false,
    this.splits,
    this.members,
  });
  final String id, merchant, payer, category;
  final DateTime date;
  final int amount;
  final bool refund, voided, personal;
  final Map<String, int>? splits;
  final List<String>? members;
  int get signedAmount => refund ? -amount : amount;
}

class Repayment {
  const Repayment({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.date,
    this.reversalOf = '',
    this.reference = '',
  });
  final String id, from, to, reversalOf, reference;
  final int amount;
  final DateTime date;
  int get signedAmount => reversalOf.isEmpty ? amount : -amount;
}

GroupSettlement financeSettlement(
  List<String> members,
  List<String> legacyMembers,
  Iterable<FinanceEntry> entries,
  Iterable<Repayment> payments,
) {
  final paid = <String, int>{for (final m in members) m: 0},
      shares = <String, int>{for (final m in members) m: 0};
  final equalTotals = <String, ({List<String> members, int amount})>{};
  var total = 0;
  for (final e in entries.where((e) => !e.personal && !e.voided)) {
    final amount = e.signedAmount;
    total += amount;
    paid.update(e.payer, (v) => v + amount, ifAbsent: () => amount);
    shares.putIfAbsent(e.payer, () => 0);
    if (e.splits != null) {
      fixedSplit(e.amount, e.splits!);
      for (final share in e.splits!.entries) {
        shares.update(
          share.key,
          (v) => v + (e.refund ? -share.value : share.value),
          ifAbsent: () => e.refund ? -share.value : share.value,
        );
        paid.putIfAbsent(share.key, () => 0);
      }
    } else {
      final ids = [...(e.members ?? legacyMembers)]..sort();
      if (ids.isEmpty) throw ArgumentError('An expense must have participants');
      final key = jsonEncode(ids);
      equalTotals[key] = (
        members: ids,
        amount: (equalTotals[key]?.amount ?? 0) + amount,
      );
    }
  }
  for (final pair in equalTotals.values) {
    final count = pair.members.length < 2 ? 2 : pair.members.length,
        absolute = pair.amount.abs(),
        sign = pair.amount < 0 ? -1 : 1;
    for (var i = 0; i < pair.members.length; i++) {
      final share = (absolute ~/ count + (i < absolute % count ? 1 : 0)) * sign;
      shares.update(pair.members[i], (v) => v + share, ifAbsent: () => share);
      paid.putIfAbsent(pair.members[i], () => 0);
    }
  }
  final balances = {
    for (final uid in paid.keys) uid: paid[uid]! - shares[uid]!,
  };
  final unique = <String, Repayment>{for (final p in payments) p.id: p};
  for (final p in unique.values) {
    if (p.from == p.to || p.amount <= 0) throw ArgumentError('Invalid payment');
    balances.update(
      p.from,
      (v) => v + p.signedAmount,
      ifAbsent: () => p.signedAmount,
    );
    balances.update(
      p.to,
      (v) => v - p.signedAmount,
      ifAbsent: () => -p.signedAmount,
    );
  }
  final transfers = <({String debtor, String creditor, int amount})>[];
  final debtors = balances.keys.where((id) => balances[id]! < 0).toList()
        ..sort(),
      creditors = balances.keys.where((id) => balances[id]! > 0).toList()
        ..sort();
  for (final from in debtors) {
    for (final to in creditors) {
      final amount = (-balances[from]!) < balances[to]!
          ? -balances[from]!
          : balances[to]!;
      if (amount <= 0) continue;
      transfers.add((debtor: from, creditor: to, amount: amount));
      balances[from] = balances[from]! + amount;
      balances[to] = balances[to]! - amount;
    }
  }
  return GroupSettlement(total, paid, shares, transfers);
}

Map<String, int> categoryTotals(Iterable<FinanceEntry> expenses) => {
  for (final category in expenseCategories)
    category: expenses
        .where(
          (e) =>
              !e.personal &&
              !e.voided &&
              (expenseCategories.contains(e.category)
                      ? e.category
                      : 'uncategorized') ==
                  category,
        )
        .fold<int>(0, (acc, e) => acc + e.signedAmount),
};
DateTime recurringDate(DateTime month, int day) {
  if (day < 1 || day > 31) throw ArgumentError('Day must be 1–31');
  final last = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, day > last ? last : day);
}

String occurrenceId(String templateId, DateTime month) =>
    'recurring_${templateId}_${monthKey(month)}';
