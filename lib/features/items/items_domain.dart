import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Exact orthographic normalization only. No fuzzy matching, translation or
/// stripping sizes: ΓΑΛΑ 1L and ΓΑΛΑ 2L remain different until a reviewed merge.
String normalizeItem(String input) {
  var value = input.trim().toLowerCase();
  const accents = {
    'ά': 'α',
    'έ': 'ε',
    'ή': 'η',
    'ί': 'ι',
    'ό': 'ο',
    'ύ': 'υ',
    'ώ': 'ω',
    'ϊ': 'ι',
    'ϋ': 'υ',
    'ΐ': 'ι',
    'ΰ': 'υ',
    'ς': 'σ',
  };
  for (final entry in accents.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }
  return value
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String itemKey(String name) =>
    sha256.convert(utf8.encode(normalizeItem(name))).toString();
String eventKey(String expense, int index) => '${expense}_$index';

const itemCategories = [
  'uncategorized',
  'food',
  'rice',
  'vegetables',
  'household',
  'utilities',
  'other',
];
const itemUnits = ['each', 'g', 'kg', 'ml', 'l'];
({int quantity, String unit}) canonicalQuantity(int milli, String unit) {
  if (milli <= 0 || milli > 100000000 || !itemUnits.contains(unit)) {
    throw ArgumentError('Invalid quantity or unit');
  }
  return switch (unit) {
    'kg' => (quantity: milli * 1000, unit: 'g'),
    'l' => (quantity: milli * 1000, unit: 'ml'),
    _ => (quantity: milli, unit: unit),
  };
}

class CatalogItem {
  const CatalogItem(
    this.id,
    this.name,
    this.category, {
    this.mergedInto = '',
    this.revision = 0,
  });
  factory CatalogItem.fromMap(String id, Map<String, dynamic> data) =>
      CatalogItem(
        id,
        data['name'] as String,
        data['category'] as String,
        mergedInto: data['mergedInto'] as String? ?? '',
        revision: data['revision'] as int? ?? 0,
      );
  final String id, name, category, mergedInto;
  final int revision;
}

String resolveItem(String id, Map<String, CatalogItem> catalog) {
  final visited = <String>{};
  var next = id;
  while (catalog[next]?.mergedInto.isNotEmpty ?? false) {
    if (!visited.add(next)) {
      throw StateError(
        'Item merge cycle detected. Undo the most recent merge.',
      );
    }
    next = catalog[next]!.mergedInto;
  }
  return next;
}

class Purchase {
  const Purchase({
    required this.id,
    required this.expenseId,
    required this.itemId,
    required this.name,
    required this.merchant,
    required this.date,
    required this.amount,
    this.quantityMilli = 1000,
    this.unit = 'each',
    this.active = true,
    this.quantityVerified = true,
  });
  final String id, expenseId, itemId, name, merchant, unit;
  final DateTime date;
  final int amount, quantityMilli;
  final bool active, quantityVerified;
  double get unitPrice => amount * 1000 / quantityMilli;
}

class ItemAnalytics {
  ItemAnalytics(this.itemId, this.unit, this.purchases);
  final String itemId, unit;
  final List<Purchase> purchases;
  int get frequency => purchases
      .where((p) => p.amount >= 0)
      .map((p) => p.expenseId)
      .toSet()
      .length;
  int get expenditure => purchases.fold(0, (sum, p) => sum + p.amount);
  int get quantity => purchases.fold(0, (sum, p) => sum + p.quantityMilli);
  Purchase get latest =>
      ([...purchases]..sort((a, b) => b.date.compareTo(a.date))).first;
  double? get averageUnitPrice {
    final known = purchases
        .where((p) => p.quantityVerified && p.amount >= 0)
        .toList();
    if (known.isEmpty) return null;
    return known.fold<int>(0, (sum, p) => sum + p.amount) *
        1000 /
        known.fold<int>(0, (sum, p) => sum + p.quantityMilli);
  }

  double? get priceMovement {
    final sorted =
        purchases.where((p) => p.quantityVerified && p.amount >= 0).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return sorted.length < 2
        ? null
        : sorted.last.unitPrice - sorted[sorted.length - 2].unitPrice;
  }
}

List<ItemAnalytics> analyzePurchases(
  Iterable<Purchase> events,
  Map<String, CatalogItem> catalog,
) {
  final unique = <String, Purchase>{
    for (final p in events)
      if (p.active) p.id: p,
  };
  final groups = <String, List<Purchase>>{};
  for (final p in unique.values) {
    final canonical = canonicalQuantity(p.quantityMilli, p.unit);
    final id = resolveItem(p.itemId, catalog);
    final key = '$id:${canonical.unit}';
    groups
        .putIfAbsent(key, () => [])
        .add(
          Purchase(
            id: p.id,
            expenseId: p.expenseId,
            itemId: id,
            name: p.name,
            merchant: p.merchant,
            date: p.date,
            amount: p.amount,
            quantityMilli: canonical.quantity,
            unit: canonical.unit,
            quantityVerified: p.quantityVerified,
          ),
        );
  }
  return groups.values
      .map((p) => ItemAnalytics(p.first.itemId, p.first.unit, p))
      .toList()
    ..sort((a, b) => b.frequency.compareTo(a.frequency));
}

class DuplicateMatch {
  const DuplicateMatch(this.expenseId, this.exactImage, this.score);
  final String expenseId;
  final bool exactImage;
  final int score;
}

String receiptSignature({
  required String merchant,
  required DateTime date,
  required int total,
  required Iterable<({String name, int amount})> items,
}) {
  final lines =
      items.map((i) => '${normalizeItem(i.name)}:${i.amount}').toList()..sort();
  return sha256
      .convert(
        utf8.encode(
          jsonEncode([
            normalizeItem(merchant),
            '${date.year}-${date.month}-${date.day}',
            total,
            lines,
          ]),
        ),
      )
      .toString();
}

/// Even an image match remains a warning with override, never automatic deletion.
List<DuplicateMatch> receiptDuplicates({
  required String signature,
  String? imageHash,
  required Iterable<Map<String, dynamic>> candidates,
}) => candidates
    .where(
      (c) =>
          c['signature'] == signature ||
          (imageHash != null && c['imageHash'] == imageHash),
    )
    .map(
      (c) => DuplicateMatch(
        c['expenseId'] as String,
        imageHash != null && c['imageHash'] == imageHash,
        c['signature'] == signature ? 4 : 2,
      ),
    )
    .toList();

Purchase correctPurchaseView(
  Purchase source,
  Map<String, dynamic>? correction,
) => correction == null
    ? source
    : Purchase(
        id: source.id,
        expenseId: source.expenseId,
        itemId: correction['itemId'] as String? ?? source.itemId,
        name: source.name,
        merchant: source.merchant,
        date: source.date,
        amount: source.amount,
        quantityMilli: correction['quantityMilli'] as int,
        unit: correction['unit'] as String,
        quantityVerified: correction['quantityVerified'] as bool,
        active: correction['active'] as bool,
      );
