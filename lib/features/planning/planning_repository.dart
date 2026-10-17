import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain.dart';
import 'planning_domain.dart';
import '../items/items_domain.dart';

class PlanningRepository {
  PlanningRepository(this.db, this.uid, this.groupId);
  final FirebaseFirestore db;
  final String uid, groupId;
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      db.collection('households').doc(groupId).collection(name);
  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String name) =>
      collection(name).snapshots(includeMetadataChanges: true);
  Stream<QuerySnapshot<Map<String, dynamic>>> expenses(
    DateTime month, {
    bool personal = false,
  }) =>
      (personal
              ? db.collection('users').doc(uid).collection('personalExpenses')
              : collection('expenses'))
          .where('month', isEqualTo: monthKey(month))
          .snapshots(includeMetadataChanges: true);
  CollectionReference<Map<String, dynamic>> get privateSignatures =>
      db.collection('users').doc(uid).collection('personalReceiptSignatures');
  Future<List<DuplicateMatch>> personalDuplicates(
    String signature,
    String? imageHash, {
    bool serverOnly = false,
  }) async {
    final matches = await privateSignatures
        .where('signature', isEqualTo: signature)
        .get(
          GetOptions(
            source: serverOnly ? Source.server : Source.serverAndCache,
          ),
        );
    final rows = {for (final d in matches.docs) d.id: d.data()};
    if (imageHash != null) {
      final images = await privateSignatures
          .where('imageHash', isEqualTo: imageHash)
          .get(
            GetOptions(
              source: serverOnly ? Source.server : Source.serverAndCache,
            ),
          );
      for (final d in images.docs) {
        rows[d.id] = d.data();
      }
    }
    return receiptDuplicates(
      signature: signature,
      imageHash: imageHash,
      candidates: rows.values,
    );
  }

  Future<void> recordPersonalSignature(
    String id,
    String signature,
    String? imageHash,
  ) async {
    final ref = privateSignatures.doc(id);
    await db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) return;
      tx.set(ref, {
        'expenseId': id,
        'signature': signature,
        'imageHash': imageHash ?? '',
        'createdBy': uid,
        'at': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> setBudget(
    String month,
    int total,
    Map<String, int> categories,
    int expectedRevision,
  ) async {
    if (total < 0 ||
        total > 1000000000 ||
        categories.keys.any((c) => !expenseCategories.contains(c)) ||
        categories.values.any((n) => n < 0 || n > 1000000000)) {
      throw ArgumentError('Invalid budget');
    }
    final ref = collection('budgets').doc(month);
    await db.runTransaction((tx) async {
      final previous = await tx.get(ref);
      if ((previous.data()?['revision'] as int? ?? -1) != expectedRevision) {
        throw StateError('Budget changed. Reload before editing.');
      }
      tx.set(ref, {
        'total': total,
        'categories': categories,
        'revision': expectedRevision + 1,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> recordPayment({
    required String id,
    required String from,
    required String to,
    required int amount,
    required DateTime date,
    String reference = '',
    String reversalOf = '',
  }) async {
    if (amount <= 0 || from == to) {
      throw ArgumentError('Enter a positive payment between different members');
    }
    final ref = collection('payments').doc(id);
    await db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) {
        final p = existing.data()!;
        if (p['from'] != from ||
            p['to'] != to ||
            p['amount'] != amount ||
            p['reversalOf'] != reversalOf) {
          throw StateError('This payment ID has different saved details.');
        }
        return;
      }
      if (reversalOf.isNotEmpty) {
        final original = await tx.get(collection('payments').doc(reversalOf));
        if (!original.exists ||
            original.data()!['reversalOf'] != '' ||
            original.data()!['from'] != from ||
            original.data()!['to'] != to ||
            original.data()!['amount'] != amount ||
            id != 'reverse_$reversalOf') {
          throw StateError('Invalid reversal.');
        }
      }
      tx.set(ref, {
        'from': from,
        'to': to,
        'amount': amount,
        'date': Timestamp.fromDate(
          DateTime.utc(date.year, date.month, date.day),
        ),
        'month': monthKey(date),
        'reference': reference,
        'reversalOf': reversalOf,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> amendExpense(
    String id, {
    required String category,
    required bool voided,
    required int expectedRevision,
  }) async {
    final ref = collection('expenses').doc(id);
    await db.runTransaction((tx) async {
      final current = await tx.get(ref);
      final row = current.data()!;
      if ((row['revision'] as int? ?? -1) != expectedRevision) {
        throw StateError('Expense changed. Reload and retry.');
      }
      final after = {'category': category, 'voided': voided};
      tx.update(ref, {
        ...after,
        'revision': expectedRevision + 1,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(
        collection('expenseChanges').doc('${id}_${expectedRevision + 1}'),
        {
          'expenseId': id,
          'revision': expectedRevision + 1,
          'before': {
            'category': row['category'] ?? 'uncategorized',
            'voided': row['voided'] ?? false,
          },
          'after': after,
          'actor': uid,
          'at': FieldValue.serverTimestamp(),
        },
      );
    });
  }

  Future<void> saveTemplate({
    required String id,
    required String merchant,
    required int amount,
    required String payer,
    required String category,
    required int day,
    required bool enabled,
    required int expectedRevision,
  }) async {
    if (merchant.trim().isEmpty || amount <= 0 || day < 1 || day > 31) {
      throw ArgumentError('Check template fields');
    }
    final ref = collection('recurring').doc(id);
    await db.runTransaction((tx) async {
      final prior = await tx.get(ref);
      if ((prior.data()?['revision'] as int? ?? -1) != expectedRevision) {
        throw StateError('Template changed. Reload and retry.');
      }
      tx.set(ref, {
        'merchant': merchant.trim(),
        'amount': amount,
        'payer': payer,
        'category': category,
        'day': day,
        'enabled': enabled,
        'revision': expectedRevision + 1,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<List<FinanceEntry>> search({
    DateTime? start,
    DateTime? end,
    String text = '',
    String category = '',
    String payer = '',
    int? minimum,
    int? maximum,
    bool includePersonal = false,
  }) async {
    final snapshot = await collection('expenses').get();
    final purchases = await collection('purchases').get();
    final terms = <String, String>{};
    for (final d in purchases.docs) {
      terms.update(
        d.data()['expenseId'] as String,
        (v) => '$v ${d.data()['name']}',
        ifAbsent: () => d.data()['name'] as String,
      );
    }
    final key = normalizeItem(text);
    final lower = start == null
        ? null
        : DateTime.utc(start.year, start.month, start.day);
    final upper = end == null
        ? null
        : DateTime.utc(
            end.year,
            end.month,
            end.day,
          ).add(const Duration(days: 1));
    final rows =
        <
          ({
            FinanceEntry entry,
            DocumentReference<Map<String, dynamic>> reference,
          })
        >[
          for (final d in snapshot.docs)
            (entry: financeFromMap(d.id, d.data()), reference: d.reference),
        ];
    if (includePersonal) {
      final own = await db
          .collection('users')
          .doc(uid)
          .collection('personalExpenses')
          .where('groupId', isEqualTo: groupId)
          .get();
      rows.addAll(
        own.docs.map(
          (d) => (
            entry: financeFromMap(d.id, d.data(), personal: true),
            reference: d.reference,
          ),
        ),
      );
    }
    final result = <FinanceEntry>[];
    for (final row in rows) {
      final e = row.entry;
      if (e.voided ||
          (lower != null && e.date.isBefore(lower)) ||
          (upper != null && !e.date.isBefore(upper)) ||
          (category.isNotEmpty && e.category != category) ||
          (payer.isNotEmpty && e.payer != payer) ||
          (minimum != null && e.amount < minimum) ||
          (maximum != null && e.amount > maximum)) {
        continue;
      }
      var haystack = '${e.merchant} ${e.personal ? '' : terms[e.id] ?? ''}';
      if (key.isNotEmpty && !normalizeItem(haystack).contains(key)) {
        final items = await row.reference.collection('items').get();
        haystack += ' ${items.docs.map((d) => d.data()['name']).join(' ')}';
      }
      if (key.isEmpty || normalizeItem(haystack).contains(key)) result.add(e);
    }
    return result..sort((a, b) => b.date.compareTo(a.date));
  }
}

FinanceEntry financeFromMap(
  String id,
  Map<String, dynamic> d, {
  bool personal = false,
}) => FinanceEntry(
  id: id,
  merchant: d['merchant'] as String,
  payer: d['payer'] as String,
  date: (d['date'] as Timestamp).toDate().toUtc(),
  amount: d['total'] as int,
  category: d['category'] as String? ?? 'uncategorized',
  refund: d['kind'] == 'refund',
  voided: d['voided'] == true,
  personal: personal || d['scope'] == 'personal',
  splits: d['splitCents'] == null
      ? null
      : Map<String, int>.from(d['splitCents'] as Map),
  members: d['splitBetween'] == null
      ? null
      : List<String>.from(d['splitBetween'] as List),
);
Repayment paymentFromMap(String id, Map<String, dynamic> d) => Repayment(
  id: id,
  from: d['from'] as String,
  to: d['to'] as String,
  amount: d['amount'] as int,
  date: (d['date'] as Timestamp).toDate().toUtc(),
  reversalOf: d['reversalOf'] as String? ?? '',
  reference: d['reference'] as String? ?? '',
);
