import 'package:basha_hisab/features/items/items_domain.dart';
import 'package:basha_hisab/features/items/items_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Purchase purchase(
  String id, {
  String name = 'Γάλα',
  int amount = 250,
  int quantity = 1000,
  String unit = 'each',
  bool verified = true,
  bool active = true,
}) => Purchase(
  id: id,
  expenseId: id,
  itemId: itemKey(name),
  name: name,
  merchant: 'Cyprus shop',
  date: DateTime(2026, 10, 17),
  amount: amount,
  quantityMilli: quantity,
  unit: unit,
  quantityVerified: verified,
  active: active,
);
void main() {
  test(
    'audited quantity and inclusion corrections recompute analytics without touching source',
    () async {
      final db = FakeFirebaseFirestore(),
          p = purchase('receipt_0', verified: false);
      final repo = ItemsRepository(db, 'a', 'home');
      await repo.collection('purchases').doc(p.id).set({
        'quantityMilli': 1000,
        'unit': 'each',
        'quantityVerified': false,
        'itemId': p.itemId,
        'active': true,
      });
      await repo.correctPurchase(
        p,
        quantityMilli: 2000,
        unit: 'each',
        active: true,
        expectedRevision: -1,
      );
      final correction =
          (await repo.collection('purchaseCorrections').doc(p.id).get())
              .data()!;
      final corrected = correctPurchaseView(p, correction);
      expect(analyzePurchases([corrected], {}).single.averageUnitPrice, 125);
      await repo.correctPurchase(
        corrected,
        quantityMilli: 2000,
        unit: 'each',
        active: false,
        expectedRevision: 0,
      );
      expect(
        analyzePurchases([
          correctPurchaseView(
            p,
            (await repo.collection('purchaseCorrections').doc(p.id).get())
                .data(),
          ),
        ], {}),
        isEmpty,
      );
      expect((await repo.collection('purchaseChanges').get()).size, 2);
      expect(
        (await repo.collection('purchases').doc(p.id).get())
            .data()!['quantityMilli'],
        1000,
      );
    },
  );
  test(
    'normalization preserves language and package identity until explicit alias',
    () {
      expect(itemKey('  ΓΆΛΑ  1L '), itemKey('γαλα 1l'));
      expect(itemKey('ΓΑΛΑ 1L'), isNot(itemKey('ΓΑΛΑ 2L')));
      expect(itemKey('Milk'), isNot(itemKey('Γάλα')));
    },
  );
  test(
    'analytics deduplicates events, excludes voids and separates incomparable units',
    () {
      final p = purchase('one');
      final stats = analyzePurchases([
        p,
        p,
        purchase('two', unit: 'kg'),
        purchase('void', active: false),
      ], {});
      expect(stats.length, 2);
      expect(stats.fold<int>(0, (s, a) => s + a.expenditure), 500);
      expect(stats.every((s) => s.frequency == 1), true);
    },
  );
  test('unknown quantities never become comparable prices', () {
    final s = analyzePurchases([
      purchase('legacy', verified: false),
    ], {}).single;
    expect(s.averageUnitPrice, isNull);
    expect(s.priceMovement, isNull);
    expect(s.frequency, 1);
  });
  test('weighted prices normalize kg to g and do not average line totals', () {
    final s = analyzePurchases([
      purchase('a', unit: 'kg', amount: 600, quantity: 2000),
      purchase('b', unit: 'g', amount: 200, quantity: 1000000),
    ], {}).single;
    expect(s.quantity, 3000000);
    expect(s.averageUnitPrice, closeTo(800 / 3000, 0.0001));
  });
  test(
    'duplicate detection warns on full characteristics or image, never same amount alone',
    () {
      final a = receiptSignature(
        merchant: 'Shop',
        date: DateTime(2026, 10, 17),
        total: 250,
        items: [(name: 'Milk', amount: 250)],
      );
      final b = receiptSignature(
        merchant: 'SHOP',
        date: DateTime(2026, 10, 17),
        total: 250,
        items: [(name: 'Rice', amount: 250)],
      );
      expect(a, isNot(b));
      expect(
        receiptDuplicates(
          signature: a,
          candidates: [
            {'expenseId': 'a', 'signature': b},
          ],
        ),
        isEmpty,
      );
      expect(
        receiptDuplicates(
          signature: a,
          imageHash: 'image',
          candidates: [
            {'expenseId': 'a', 'signature': b, 'imageHash': 'image'},
          ],
        ).single.exactImage,
        true,
      );
    },
  );
  test(
    'purchase indexing and backfill repeat without changing source data or counts',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = ItemsRepository(db, 'a', 'home');
      await db.doc('households/home/expenses/e').set({
        'itemCount': 1,
        'merchant': 'Shop',
        'date': Timestamp.fromDate(DateTime(2026)),
      });
      await db.doc('households/home/expenses/e/items/0').set({
        'name': 'Γάλα',
        'amount': 250,
        'index': 0,
      });
      await repo.indexExpense('e');
      await repo.backfill();
      await repo.backfill();
      expect((await repo.collection('purchases').get()).size, 1);
      expect((await repo.collection('catalog').get()).size, 1);
      expect(
        (await db.doc('households/home/expenses/e/items/0').get())
            .data()!['amount'],
        250,
      );
    },
  );
  test(
    'shopping merges only distinct operations; checkbox is unrelated to purchases',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = ItemsRepository(db, 'a', 'home');
      final id = itemKey('Milk');
      Future<void> add(String op) => repo.addShopping(
        itemId: id,
        name: 'Milk',
        quantityMilli: 1000,
        unit: 'each',
        operationId: op,
      );
      await add('one');
      await add('one');
      await add('two');
      final row = (await repo.collection('shopping').get()).docs.single;
      expect(row.data()['quantityMilli'], 2000);
      await repo.changeShopping(
        row.id,
        row.data()['revision'] as int,
        checked: true,
        assignedTo: '',
        notes: '',
      );
      expect((await repo.collection('purchases').get()).size, 0);
    },
  );
  test(
    'restock and consume are idempotent and cannot consume negative stock',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = ItemsRepository(db, 'a', 'home');
      final p = purchase('e_0');
      await repo.restock(p, quantityMilli: 2000, unit: 'each');
      await repo.restock(p, quantityMilli: 2000, unit: 'each');
      await repo.consume('receipt_e_0', 500, 'consume1');
      await repo.consume('receipt_e_0', 500, 'consume1');
      expect(
        (await repo.collection('stock').doc('receipt_e_0').get())
            .data()!['quantityMilli'],
        1500,
      );
      await expectLater(
        repo.consume('receipt_e_0', 2000, 'consume2'),
        throwsStateError,
      );
    },
  );
  test(
    'correction, merge and undo retain purchase events and aliases',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = ItemsRepository(db, 'a', 'home');
      final a = itemKey('Milk'), b = itemKey('Γάλα');
      for (final id in [a, b]) {
        await repo.collection('catalog').doc(id).set({
          'name': id == a ? 'Milk' : 'Γάλα',
          'category': 'uncategorized',
          'mergedInto': '',
          'revision': 0,
        });
      }
      final item = CatalogItem.fromMap(
        a,
        (await repo.collection('catalog').doc(a).get()).data()!,
      );
      await repo.correctItem(
        item,
        name: 'Milk',
        category: 'food',
        mergedInto: b,
      );
      final merged = CatalogItem.fromMap(
        a,
        (await repo.collection('catalog').doc(a).get()).data()!,
      );
      expect(resolveItem(a, {a: merged}), b);
      await repo.undoItem(merged);
      expect(
        (await repo.collection('catalog').doc(a).get()).data()!['mergedInto'],
        '',
      );
      expect((await repo.collection('catalogChanges').get()).size, 2);
    },
  );
}
