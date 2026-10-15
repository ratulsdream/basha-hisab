import 'dart:math';

/// Monetary amounts are integers in the currency's smallest unit (two decimals).
int? parseMoney(String input) {
  final raw = input.trim();
  if (!RegExp(
    r'^(?:\d{1,8}|\d{1,3}(?:,\d{3}){1,2})(?:\.\d{1,2})?$',
  ).hasMatch(raw)) {
    return null;
  }
  final text = raw.replaceAll(',', '');
  if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final result =
      int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return result <= 1000000000 ? result : null;
}

String moneyInput(int cents) => (cents / 100).toStringAsFixed(2);
String monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

class ExpenseItem {
  const ExpenseItem(this.name, this.amount);
  final String name;
  final int amount;
  Map<String, Object> toMap() => {'name': name, 'amount': amount};
}

class ReceiptDraft {
  const ReceiptDraft({
    this.merchant = '',
    this.date,
    this.total,
    this.items = const [],
    this.rawText = '',
  });
  final String merchant;
  final DateTime? date;
  final int? total;
  final List<ExpenseItem> items;
  final String rawText;
}

/// OCR is a suggestion only. Never persist this result without explicit review.
ReceiptDraft parseReceipt(String text) {
  final lines = text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final pricePattern = RegExp(
    r'(\d{1,3}(?:,\d{3})*\.\d{2}|\d{1,8}\.\d{2})\s*(?:[A-Z]{0,3})?$',
  );
  final totalPattern = RegExp(
    r'\b(grand\s*total|total\s*due|amount\s*due|balance\s*due|total)\b',
    caseSensitive: false,
  );
  final excluded = RegExp(
    r'\b(subtotal|sub total|tax|vat|change|cash|card|discount|tender|saving|balance)\b',
    caseSensitive: false,
  );
  int? total;
  DateTime? date;
  final items = <ExpenseItem>[];
  for (final line in lines) {
    final dateMatch = RegExp(
      r'\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b',
    ).firstMatch(line);
    final localMatch = RegExp(
      r'\b(\d{1,2})[-/](\d{1,2})[-/](\d{4})\b',
    ).firstMatch(line);
    if (dateMatch != null || localMatch != null) {
      final match = dateMatch ?? localMatch!;
      final year = int.parse(match.group(dateMatch != null ? 1 : 3)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(dateMatch != null ? 3 : 1)!);
      final candidate = DateTime(year, month, day);
      if (year >= 2000 &&
          year <= 2100 &&
          candidate.year == year &&
          candidate.month == month &&
          candidate.day == day) {
        date = candidate;
      }
    }
    final price = pricePattern.firstMatch(line);
    if (price == null) continue;
    final amount = parseMoney(price.group(1)!);
    if (amount == null) continue;
    if (totalPattern.hasMatch(line) &&
        !RegExp(r'\bsub\s*total\b', caseSensitive: false).hasMatch(line)) {
      total = amount;
    } else if (!excluded.hasMatch(line)) {
      final name = line
          .substring(0, price.start)
          .replaceAll(RegExp(r'[\s:$€£৳]+$'), '')
          .trim();
      if (name.isNotEmpty && items.length < 100) {
        items.add(ExpenseItem(name, amount));
      }
    }
  }
  final merchant =
      lines
          .where(
            (line) =>
                RegExp(r'[A-Za-z]').hasMatch(line) &&
                !pricePattern.hasMatch(line),
          )
          .firstOrNull ??
      '';
  return ReceiptDraft(
    merchant: merchant,
    date: date,
    total: total,
    items: items,
    rawText: text,
  );
}

class Settlement {
  const Settlement({
    required this.total,
    required this.paid,
    required this.shares,
    this.debtor,
    this.creditor,
    required this.amount,
  });
  final int total;
  final Map<String, int> paid;
  final Map<String, int> shares;
  final String? debtor;
  final String? creditor;
  final int amount;
}

Settlement calculateSettlement(
  List<String> members,
  Iterable<({String payer, int amount})> expenses,
) {
  if (members.isEmpty ||
      members.length > 2 ||
      members.toSet().length != members.length) {
    throw ArgumentError('One or two distinct household members are required.');
  }
  final ids = [...members]..sort();
  final paid = {for (final id in ids) id: 0};
  var total = 0;
  for (final expense in expenses) {
    if (!paid.containsKey(expense.payer) || expense.amount < 0) {
      throw ArgumentError('Invalid expense.');
    }
    paid[expense.payer] = paid[expense.payer]! + expense.amount;
    total += expense.amount;
  }
  // Reserve the second roommate's half while waiting for them to join.
  final shares = {ids.first: (total + 1) ~/ 2};
  if (ids.length == 2) shares[ids[1]] = total ~/ 2;
  final difference = paid[ids.first]! - shares[ids.first]!;
  return Settlement(
    total: total,
    paid: paid,
    shares: shares,
    debtor: ids.length == 2 && difference != 0
        ? (difference > 0 ? ids[1] : ids.first)
        : null,
    creditor: ids.length == 2 && difference != 0
        ? (difference > 0 ? ids.first : ids[1])
        : null,
    amount: ids.length == 2 ? difference.abs() : 0,
  );
}

String newInviteCode() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
