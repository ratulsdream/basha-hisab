import 'dart:math';
import 'dart:convert';

/// Monetary amounts are integers in the currency's smallest unit (two decimals).
int? parseMoney(String input) {
  var text = input.trim().replaceAll(RegExp(r'^[€$£]\s*|\s*[€$£]$'), '');
  if (!RegExp(r'^\d[\d.,]*$').hasMatch(text)) return null;
  final comma = text.lastIndexOf(',');
  final dot = text.lastIndexOf('.');
  final last = max(comma, dot);
  String integer, fraction;
  if (last < 0) {
    integer = text;
    fraction = '';
  } else {
    final separator = text[last];
    final tail = text.substring(last + 1);
    // A single separator with three trailing digits is ambiguous; ask for correction.
    if (tail.isEmpty || tail.length > 2) return null;
    integer = text.substring(0, last);
    fraction = tail;
    final grouping = separator == ',' ? '.' : ',';
    if (integer.contains(separator)) return null;
    if (integer.contains(grouping)) {
      final escaped = RegExp.escape(grouping);
      if (!RegExp('^\\d{1,3}(?:$escaped\\d{3})+\$').hasMatch(integer)) {
        return null;
      }
      integer = integer.replaceAll(grouping, '');
    }
  }
  if (!RegExp(r'^\d{1,8}$').hasMatch(integer)) return null;
  final result =
      int.parse(integer) * 100 +
      (fraction.isEmpty ? 0 : int.parse(fraction.padRight(2, '0')));
  return result <= 1000000000 ? result : null;
}

String moneyInput(int cents) => (cents / 100).toStringAsFixed(2);
String monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

class ExpenseItem {
  const ExpenseItem(this.name, this.amount, {this.quantityMilli, this.unit});
  final String name;
  final int amount;
  final int? quantityMilli;
  final String? unit;
  Map<String, Object> toMap({bool includeQuantity = false}) => {
    'name': name,
    'amount': amount,
    if (includeQuantity && quantityMilli != null) ...{
      'quantityMilli': quantityMilli!,
      'unit': unit ?? 'each',
    },
  };
}

class ReceiptDraft {
  const ReceiptDraft({
    this.merchant = '',
    this.date,
    this.total,
    this.items = const [],
    this.rawText = '',
    this.warnings = const [],
    this.imageHash,
  });
  final String merchant;
  final DateTime? date;
  final int? total;
  final List<ExpenseItem> items;
  final String rawText;
  final List<String> warnings;
  final String? imageHash;
}

/// Normalize Greek tonos and final sigma for matching, preserving original display text.
String receiptKeywords(String text) {
  var result = text.toUpperCase();
  const accents = {
    'Ά': 'Α',
    'Έ': 'Ε',
    'Ή': 'Η',
    'Ί': 'Ι',
    'Ό': 'Ο',
    'Ύ': 'Υ',
    'Ώ': 'Ω',
    'Ϊ': 'Ι',
    'Ϋ': 'Υ',
  };
  for (final entry in accents.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  result = result.replaceAll(RegExp(r'[\u0300-\u036f]'), '');
  // Tesseract may render Greek capitals with visually identical Latin glyphs.
  return result.replaceAll(
    RegExp(
      r'(?<![A-ZΑ-Ω])(?:Σ|S|Z)[ΥYUV](?:Ν|N)[ΟO0](?:Λ|L|A|Δ)[ΟO0](?![A-ZΑ-Ω])',
    ),
    'ΣΥΝΟΛΟ',
  );
}

/// Suggestions only: no database access, no auto-save, no invented totals.
ReceiptDraft parseReceipt(String text) {
  final lines = text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final pricePattern = RegExp(
    r'([€£$]?\s*\d+(?:[.,]\d{3})*[.,]\d{2})\s*(?:€|EUR|[A-ZΑ-Ω]{1,2})?$',
    caseSensitive: false,
  );
  final totalPattern = RegExp(
    r'(?:^|[^A-ZΑ-Ω])(GRAND\s+TOTAL|TOTAL(?:\s+DUE)?|AMOUNT\s+DUE|BALANCE\s+DUE|ΓΕΝΙΚΟ\s+ΣΥΝΟΛΟ|ΣΥΝΟΛΟ|ΠΛΗΡΩΤΕΟ)(?:$|[^A-ZΑ-Ω])',
  );
  final excluded = RegExp(
    r'(?:^|[^A-ZΑ-Ω])(SUB\s*TOTAL|VAT|TAX|Φ\.?Π\.?Α\.?|ΜΕΡΙΚΟ\s+ΣΥΝΟΛΟ|ΕΚΠΤΩΣΗ|ΜΕΤΡΗΤΑ|ΚΑΡΤΑ|ΡΕΣΤΑ|CASH|CARD|CHANGE|DISCOUNT|TENDER|SAVINGS?|BALANCE)(?:$|[^A-ZΑ-Ω])',
  );
  final totals = <int>[];
  DateTime? date;
  final items = <ExpenseItem>[];
  String merchant = '';
  final warnings = <String>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final key = receiptKeywords(line);
    final iso = RegExp(
      r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b',
    ).firstMatch(line);
    final eu = RegExp(
      r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})\b',
    ).firstMatch(line);
    final match = iso ?? eu;
    if (match != null) {
      var year = int.parse(match.group(iso != null ? 1 : 3)!);
      if (year < 100) {
        year += 2000; // Receipt dates are restricted to 2000–2100.
      }
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(iso != null ? 3 : 1)!);
      final candidate = DateTime(year, month, day);
      if (year >= 2000 &&
          year <= 2100 &&
          candidate.year == year &&
          candidate.month == month &&
          candidate.day == day) {
        date ??= candidate;
      }
      continue;
    }
    if (excluded.hasMatch(key)) continue;
    final price = pricePattern.firstMatch(line);
    final isTotal = totalPattern.hasMatch(key);
    if (isTotal) {
      var amount = price == null ? null : parseMoney(price.group(1)!.trim());
      if (amount == null && index + 1 < lines.length) {
        // Many till layouts print the total value on the following line.
        final next = lines[index + 1].trim();
        amount = parseMoney(next);
      }
      if (amount != null && amount > 0) totals.add(amount);
      continue;
    }
    if (price != null) {
      final amount = parseMoney(price.group(1)!.trim());
      var name = line
          .substring(0, price.start)
          .replaceAll(RegExp(r'[\s:€£$]+$'), '')
          .trim();
      // Retain explicit quantity/unit as suggestions, never infer package size.
      final quantityPattern = RegExp(
        r'\s+(\d+(?:[.,]\d{1,3})?)\s*(kg|g|ml|l)?\s*[xX×*]\s*€?\s*\d+[.,]\d{2}\s*$',
        caseSensitive: false,
      );
      final quantityMatch = quantityPattern.firstMatch(name);
      int? quantityMilli;
      String? unit;
      if (quantityMatch != null) {
        final parts = quantityMatch.group(1)!.replaceAll(',', '.').split('.');
        quantityMilli =
            int.parse(parts[0]) * 1000 +
            (parts.length == 1 ? 0 : int.parse(parts[1].padRight(3, '0')));
        unit = quantityMatch.group(2)?.toLowerCase() ?? 'each';
        if (quantityMilli <= 0 || quantityMilli > 100000000) {
          quantityMilli = null;
          unit = null;
        }
        name = name.substring(0, quantityMatch.start).trim();
      }
      if (amount != null &&
          RegExp(r'[A-Za-z\u0370-\u03ff\u1f00-\u1fff]').hasMatch(name) &&
          items.length < 100) {
        items.add(
          ExpenseItem(name, amount, quantityMilli: quantityMilli, unit: unit),
        );
      }
    } else if (merchant.isEmpty &&
        RegExp(r'[A-Za-z\u0370-\u03ff\u1f00-\u1fff]').hasMatch(line) &&
        !RegExp(
          r'^(TEL|ΤΗΛ|ΑΦΜ|RECEIPT|ΑΠΟΔΕΙΞΗ)',
          caseSensitive: false,
        ).hasMatch(line)) {
      merchant = line;
    }
  }
  final total = totals.lastOrNull;
  if (merchant.isEmpty) warnings.add('Merchant not detected');
  if (date == null) warnings.add('Date not detected — choose the receipt date');
  if (total == null) warnings.add('Total not detected');
  if (totals.toSet().length > 1) {
    warnings.add('Conflicting total amounts — check the printed total');
  }
  if (items.isEmpty) warnings.add('No line items detected');
  if (items.isNotEmpty &&
      total != null &&
      items.fold<int>(0, (sum, i) => sum + i.amount) != total) {
    warnings.add('Items do not add up to the receipt total');
  }
  return ReceiptDraft(
    merchant: merchant,
    date: date,
    total: total,
    items: items,
    rawText: text,
    warnings: warnings,
  );
}

int receiptScore(ReceiptDraft draft) =>
    (draft.total != null ? 12 : 0) +
    (draft.date != null ? 4 : 0) +
    (draft.merchant.isNotEmpty ? 2 : 0) +
    min<int>(draft.items.length, 12) -
    draft.warnings.length;

/// Select a complete pass; concatenating OCR passes would duplicate charged items.
ReceiptDraft selectReceiptPass(String original, String enhanced) {
  final first = parseReceipt(original), second = parseReceipt(enhanced);
  final chosen = receiptScore(second) > receiptScore(first) ? second : first;
  return ReceiptDraft(
    merchant: chosen.merchant,
    date: chosen.date,
    total: chosen.total,
    items: chosen.items,
    warnings: [
      ...chosen.warnings,
      if (first.total != null &&
          second.total != null &&
          first.total != second.total)
        'OCR passes disagree on total — check the printed amount',
    ],
    rawText: 'ORIGINAL IMAGE\n$original\n\nENHANCED IMAGE\n$enhanced',
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

/// Each v2 expense freezes its participants. Historical balances survive leaving
/// and replacing a roommate without reallocating old purchases to new members.
class GroupSettlement {
  const GroupSettlement(this.total, this.paid, this.shares, this.transfers);
  final int total;
  final Map<String, int> paid, shares;
  final List<({String debtor, String creditor, int amount})> transfers;
}

GroupSettlement calculateGroupSettlement(
  List<String> currentMembers,
  List<String> legacyMembers,
  Iterable<({String payer, int amount, List<String>? splitBetween})> expenses,
) {
  final paid = <String, int>{for (final uid in currentMembers) uid: 0};
  final shares = <String, int>{for (final uid in currentMembers) uid: 0};
  var total = 0;
  final splitTotals = <String, ({List<String> participants, int amount})>{};
  for (final expense in expenses) {
    final participants = [...(expense.splitBetween ?? legacyMembers)]..sort();
    if (participants.isEmpty || expense.amount < 0) {
      throw ArgumentError('Invalid expense participants');
    }
    paid.update(
      expense.payer,
      (value) => value + expense.amount,
      ifAbsent: () => expense.amount,
    );
    shares.putIfAbsent(expense.payer, () => 0);
    final key = jsonEncode(participants);
    final previous = splitTotals[key]?.amount ?? 0;
    splitTotals[key] = (
      participants: participants,
      amount: previous + expense.amount,
    );
    total += expense.amount;
  }
  // Preserve v1 monthly rounding for each stable roommate pair, rather than
  // charging the same person an extra cent on every odd-priced purchase.
  for (final split in splitTotals.values) {
    final participants = split.participants;
    final denominator = max(2, participants.length);
    for (var i = 0; i < participants.length; i++) {
      final share =
          split.amount ~/ denominator +
          (i < split.amount % denominator ? 1 : 0);
      shares.update(
        participants[i],
        (value) => value + share,
        ifAbsent: () => share,
      );
      paid.putIfAbsent(participants[i], () => 0);
    }
  }
  final balances = {
    for (final uid in paid.keys) uid: paid[uid]! - shares[uid]!,
  };
  final transfers = <({String debtor, String creditor, int amount})>[];
  final debtors = balances.keys.where((uid) => balances[uid]! < 0).toList()
    ..sort();
  final creditors = balances.keys.where((uid) => balances[uid]! > 0).toList()
    ..sort();
  for (final debtor in debtors) {
    for (final creditor in creditors) {
      final amount = min(-balances[debtor]!, balances[creditor]!);
      if (amount <= 0) continue;
      transfers.add((debtor: debtor, creditor: creditor, amount: amount));
      balances[debtor] = balances[debtor]! + amount;
      balances[creditor] = balances[creditor]! - amount;
    }
  }
  return GroupSettlement(total, paid, shares, transfers);
}
