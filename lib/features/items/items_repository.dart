import 'package:cloud_firestore/cloud_firestore.dart';
import 'items_domain.dart';

class ItemsRepository {
  ItemsRepository(this.db, this.uid, this.groupId);
  final FirebaseFirestore db;
  final String uid, groupId;
  DocumentReference<Map<String, dynamic>> get group =>
      db.collection('households').doc(groupId);
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      group.collection(path);
  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String path) =>
      collection(path).snapshots(includeMetadataChanges: true);
  Future<void> indexExpense(String expenseId) async {
    final expense = await collection('expenses').doc(expenseId).get();
    if (!expense.exists) {
      throw StateError(
        'Expense not yet confirmed by the server. Retry after syncing.',
      );
    }
    final data = expense.data()!;
    final lines = await expense.reference.collection('items').get();
    if (lines.size != data['itemCount']) {
      throw StateError(
        'Item details are incomplete. Reconnect before indexing.',
      );
    }
    for (final line in lines.docs) {
      final row = line.data();
      final name = row['name'] as String;
      final alias = collection('itemAliases').doc(itemKey(name));
      final event = collection(
        'purchases',
      ).doc(eventKey(expenseId, row['index'] as int));
      await db.runTransaction((tx) async {
        final old = await tx.get(event);
        if (old.exists) return;
        final mapping = await tx.get(alias);
        final id = mapping.data()?['active'] == false
            ? itemKey(name)
            : (mapping.data()?['itemId'] as String? ?? itemKey(name));
        final item = collection('catalog').doc(id);
        final exists = await tx.get(item);
        if (!exists.exists) {
          tx.set(item, {
            'name': name,
            'category': 'uncategorized',
            'mergedInto': '',
            'revision': 0,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': uid,
          });
        }
        if (!mapping.exists) {
          tx.set(alias, {
            'itemId': id,
            'alias': normalizeItem(name),
            'active': true,
            'revision': 0,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': uid,
          });
        }
        tx.set(event, {
          'expenseId': expenseId,
          'itemIndex': row['index'],
          'itemId': id,
          'name': name,
          'amount': data['kind'] == 'refund'
              ? -(row['amount'] as int)
              : row['amount'],
          'merchant': data['merchant'],
          'date': data['date'],
          'quantityMilli': row['quantityMilli'] ?? 1000,
          'unit': row['unit'] ?? 'each',
          'quantityVerified': row.containsKey('quantityMilli'),
          'active': true,
          'createdBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    }
  }

  /// Explicit, resumable by deterministic expense/line event IDs; never mutates source expenses.
  Future<int> backfill({void Function(int count)? onProgress}) async {
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    var count = 0;
    while (true) {
      Query<Map<String, dynamic>> query = collection(
        'expenses',
      ).orderBy(FieldPath.documentId).limit(20);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query.get();
      if (page.docs.isEmpty) return count;
      for (final doc in page.docs) {
        await indexExpense(doc.id);
        count++;
        onProgress?.call(count);
      }
      cursor = page.docs.last;
      if (page.docs.length < 20) return count;
    }
  }

  Future<void> correctItem(
    CatalogItem item, {
    required String name,
    required String category,
    String? mergedInto,
  }) async {
    if (name.trim().isEmpty ||
        name.trim().length > 100 ||
        !itemCategories.contains(category)) {
      throw ArgumentError('Invalid item details');
    }
    final reference = collection('catalog').doc(item.id);
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(reference);
      final before = snapshot.data()!;
      if (before['revision'] != item.revision) {
        throw StateError(
          'Another member changed this item. Reload before correcting it.',
        );
      }
      final target = mergedInto ?? before['mergedInto'] as String;
      if (target.isNotEmpty) {
        final destination = await tx.get(collection('catalog').doc(target));
        if (!destination.exists ||
            target == item.id ||
            destination.data()!['mergedInto'] != '') {
          throw StateError(
            'Choose a separate canonical item. This merge target changed; reload and retry.',
          );
        }
      }
      final after = {
        'name': name.trim(),
        'category': category,
        'mergedInto': target,
      };
      final revision = item.revision + 1;
      tx.update(reference, {
        ...after,
        'revision': revision,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(collection('catalogChanges').doc('${item.id}_$revision'), {
        'itemId': item.id,
        'revision': revision,
        'before': {
          for (final k in ['name', 'category', 'mergedInto']) k: before[k],
        },
        'after': after,
        'actor': uid,
        'at': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> undoItem(CatalogItem item) async {
    final change = await collection(
      'catalogChanges',
    ).doc('${item.id}_${item.revision}').get();
    if (!change.exists) throw StateError('No correction to undo.');
    final before = Map<String, dynamic>.from(change.data()!['before'] as Map);
    await correctItem(
      item,
      name: before['name'] as String,
      category: before['category'] as String,
      mergedInto: before['mergedInto'] as String,
    );
  }

  Future<void> addAlias(
    String name,
    String itemId, {
    bool active = true,
  }) async {
    final ref = collection('itemAliases').doc(itemKey(name));
    await db.runTransaction((tx) async {
      final prior = await tx.get(ref);
      final data = prior.data();
      if (data != null && data['itemId'] != itemId && data['active'] != false) {
        throw StateError(
          'That alias belongs to another item. Disable it there before explicitly assigning it elsewhere.',
        );
      }
      if (data != null &&
          data['itemId'] == itemId &&
          data['active'] == active) {
        return;
      }
      if (data == null && !active) throw StateError('Alias not found.');
      final revision = (data?['revision'] as int? ?? -1) + 1;
      tx.set(ref, {
        'itemId': itemId,
        'alias': normalizeItem(name),
        'active': active,
        'revision': revision,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
      if (data != null) {
        tx.set(collection('aliasChanges').doc('${ref.id}_$revision'), {
          'aliasId': ref.id,
          'revision': revision,
          'before': {'itemId': data['itemId'], 'active': data['active']},
          'after': {'itemId': itemId, 'active': active},
          'actor': uid,
          'at': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> addShopping({
    required String itemId,
    required String name,
    required int quantityMilli,
    required String unit,
    String assignedTo = '',
    String notes = '',
    String? operationId,
  }) async {
    canonicalQuantity(quantityMilli, unit);
    final operation = collection(
      'shoppingEvents',
    ).doc(operationId ?? collection('shoppingEvents').doc().id);
    final id = '${itemId}_$unit';
    final ref = collection('shopping').doc(id);
    await db.runTransaction((tx) async {
      final committed = await tx.get(operation);
      if (committed.exists) return;
      final old = await tx.get(ref);
      final prior = old.data();
      tx.set(ref, {
        'itemId': itemId,
        'name': name,
        'lastAdd': operation.id,
        'quantityMilli':
            quantityMilli +
            (prior != null && prior['checked'] == false
                ? prior['quantityMilli'] as int
                : 0),
        'unit': unit,
        'checked': false,
        'assignedTo': assignedTo,
        'notes': notes,
        'revision': (prior?['revision'] as int? ?? -1) + 1,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(operation, {
        'listId': id,
        'deltaMilli': quantityMilli,
        'actor': uid,
        'at': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> changeShopping(
    String id,
    int revision, {
    required bool checked,
    required String assignedTo,
    required String notes,
  }) async {
    final ref = collection('shopping').doc(id);
    await db.runTransaction((tx) async {
      final old = await tx.get(ref);
      if (old.data()?['revision'] != revision) {
        throw StateError('Shopping list changed. Reload and retry.');
      }
      tx.update(ref, {
        'checked': checked,
        'assignedTo': assignedTo,
        'notes': notes,
        'revision': revision + 1,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// One reviewed restock per purchased line; neither indexing nor checking a list restocks automatically.
  Future<void> correctPurchase(
    Purchase purchase, {
    required int quantityMilli,
    required String unit,
    required bool active,
    required int expectedRevision,
    String? itemId,
  }) async {
    canonicalQuantity(quantityMilli, unit);
    final ref = collection('purchaseCorrections').doc(purchase.id);
    await db.runTransaction((tx) async {
      final source = await tx.get(collection('purchases').doc(purchase.id));
      final old = await tx.get(ref);
      if (!source.exists) throw StateError('The purchase could not be found.');
      final revision = old.data()?['revision'] as int? ?? -1;
      if (revision != expectedRevision) {
        throw StateError(
          'Another member corrected this purchase. Reload and retry.',
        );
      }
      final before = old.data() ?? source.data()!;
      final after = {
        'itemId': itemId ?? purchase.itemId,
        'quantityMilli': quantityMilli,
        'unit': unit,
        'quantityVerified': true,
        'active': active,
      };
      tx.set(ref, {
        ...after,
        'revision': revision + 1,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(
        collection('purchaseChanges').doc('${purchase.id}_${revision + 1}'),
        {
          'purchaseId': purchase.id,
          'revision': revision + 1,
          'before': {
            for (final k in [
              'itemId',
              'quantityMilli',
              'unit',
              'quantityVerified',
              'active',
            ])
              k: before[k],
          },
          'after': after,
          'actor': uid,
          'at': FieldValue.serverTimestamp(),
        },
      );
    });
  }

  Future<List<DuplicateMatch>> duplicates(
    String signature,
    String? imageHash, {
    bool serverOnly = false,
  }) async {
    final snapshot = await collection('receiptSignatures')
        .where('signature', isEqualTo: signature)
        .get(
          GetOptions(
            source: serverOnly ? Source.server : Source.serverAndCache,
          ),
        );
    final rows = <String, Map<String, dynamic>>{
      for (final d in snapshot.docs) d.id: d.data(),
    };
    if (imageHash != null && imageHash.isNotEmpty) {
      final images = await collection('receiptSignatures')
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

  Future<void> recordSignature(
    String expenseId,
    String signature,
    String? imageHash,
  ) async {
    final ref = collection('receiptSignatures').doc(expenseId);
    await db.runTransaction((tx) async {
      final prior = await tx.get(ref);
      if (prior.exists) return;
      tx.set(ref, {
        'expenseId': expenseId,
        'signature': signature,
        'imageHash': imageHash ?? '',
        'createdBy': uid,
        'at': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> restock(
    Purchase purchase, {
    required int quantityMilli,
    required String unit,
    DateTime? expiry,
    int lowStockMilli = 1000,
  }) async {
    canonicalQuantity(quantityMilli, unit);
    final id = 'receipt_${purchase.id}';
    final lot = collection('stock').doc(id),
        event = collection('stockEvents').doc(id);
    await db.runTransaction((tx) async {
      final exists = await tx.get(event);
      if (exists.exists) return;
      tx.set(lot, {
        'itemId': purchase.itemId,
        'name': purchase.name,
        'unit': unit,
        'quantityMilli': quantityMilli,
        'lowStockMilli': lowStockMilli,
        'expiry': expiry == null
            ? null
            : Timestamp.fromDate(
                DateTime.utc(expiry.year, expiry.month, expiry.day),
              ),
        'lastEvent': id,
        'revision': 0,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(event, {
        'lotId': id,
        'purchaseId': purchase.id,
        'deltaMilli': quantityMilli,
        'actor': uid,
        'at': FieldValue.serverTimestamp(),
        'kind': 'restock',
      });
    });
  }

  Future<void> consume(String id, int quantityMilli, String operationId) async {
    if (quantityMilli <= 0) throw ArgumentError('Enter positive consumption');
    final lot = collection('stock').doc(id),
        event = collection('stockEvents').doc(operationId);
    await db.runTransaction((tx) async {
      final prior = await tx.get(event);
      if (prior.exists) return;
      final snapshot = await tx.get(lot);
      final row = snapshot.data()!;
      final remaining = (row['quantityMilli'] as int) - quantityMilli;
      if (remaining < 0) {
        throw StateError('Consumption exceeds available stock.');
      }
      tx.update(lot, {
        'quantityMilli': remaining,
        'revision': (row['revision'] as int) + 1,
        'lastEvent': operationId,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(event, {
        'lotId': id,
        'purchaseId': '',
        'deltaMilli': -quantityMilli,
        'actor': uid,
        'at': FieldValue.serverTimestamp(),
        'kind': 'consume',
      });
    });
  }
}

Purchase purchaseFromMap(String id, Map<String, dynamic> d) => Purchase(
  id: id,
  expenseId: d['expenseId'] as String,
  itemId: d['itemId'] as String,
  name: d['name'] as String,
  merchant: d['merchant'] as String,
  date: (d['date'] as Timestamp).toDate(),
  amount: d['amount'] as int,
  quantityMilli: d['quantityMilli'] as int,
  unit: d['unit'] as String,
  active: d['active'] as bool,
  quantityVerified: d['quantityVerified'] as bool,
);
