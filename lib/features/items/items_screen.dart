import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../data.dart';
import '../../widgets/common.dart';
import 'items_domain.dart';
import 'items_repository.dart';
import 'items_tabs.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({
    super.key,
    required this.repository,
    required this.household,
    required this.enabled,
  });
  final ItemsRepository repository;
  final Household household;
  final bool enabled;
  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _catalog = widget.repository
      .watch('catalog');
  late Stream<QuerySnapshot<Map<String, dynamic>>> _purchases = widget
      .repository
      .watch('purchases');
  late Stream<QuerySnapshot<Map<String, dynamic>>> _shopping = widget.repository
      .watch('shopping');
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stock = widget.repository
      .watch('stock');
  late Stream<QuerySnapshot<Map<String, dynamic>>> _corrections = widget
      .repository
      .watch('purchaseCorrections');
  late Stream<QuerySnapshot<Map<String, dynamic>>> _financial = widget
      .repository
      .watch('expenses');
  void _reload() => setState(() {
    _financial = widget.repository.watch('expenses');
    _catalog = widget.repository.watch('catalog');
    _purchases = widget.repository.watch('purchases');
    _shopping = widget.repository.watch('shopping');
    _stock = widget.repository.watch('stock');
    _corrections = widget.repository.watch('purchaseCorrections');
  });
  bool _busy = false;
  String? _progress;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backfill() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import historical items?'),
        content: const Text(
          'Read existing item details and create a shared library. Expenses stay unchanged. Repeating an interrupted import does not duplicate purchases. Missing quantities remain unknown.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final count = await widget.repository.backfill(
        onProgress: (n) {
          if (mounted) setState(() => _progress = 'Imported $n expenses…');
        },
      );
      if (mounted) {
        setState(() => _progress = 'Import complete: $count expenses checked');
      }
    });
  }

  Future<void> _edit(CatalogItem item, Map<String, CatalogItem> catalog) async {
    final name = TextEditingController(text: item.name),
        alias = TextEditingController();
    var removeAlias = false;
    var category = item.category;
    var target = item.mergedInto;
    String existingAliases = '';
    try {
      final aliases = await widget.repository
          .collection('itemAliases')
          .where('itemId', isEqualTo: item.id)
          .get();
      existingAliases = aliases.docs
          .where((d) => d.data()['active'] != false)
          .map((d) => d.data()['alias'])
          .join(', ');
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Correct library item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Item name'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  items: itemCategories
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => update(() => category = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: alias,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: 'Optional Greek/English alias',
                    helperText: 'Active: $existingAliases',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: target,
                  decoration: const InputDecoration(
                    labelText: 'Reviewed merge into',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Keep separate'),
                    ),
                    for (final candidate in catalog.values)
                      if (candidate.id != item.id &&
                          candidate.mergedInto.isEmpty)
                        DropdownMenuItem(
                          value: candidate.id,
                          child: Text(candidate.name),
                        ),
                  ],
                  onChanged: (v) => update(() => target = v!),
                ),
                CheckboxListTile(
                  value: removeAlias,
                  onChanged: (v) => update(() => removeAlias = v!),
                  title: const Text(
                    'Disable entered alias instead of adding it',
                  ),
                ),
                const Text(
                  'Merging never deletes history. Undo restores the previous correction.',
                ),
              ],
            ),
          ),
          actions: [
            if (item.revision > 0)
              TextButton(
                onPressed: () => Navigator.pop(context, 'undo'),
                child: const Text('Undo last correction'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (action != null) {
      await _run(() async {
        if (action == 'undo') {
          await widget.repository.undoItem(item);
          return;
        }
        await widget.repository.correctItem(
          item,
          name: name.text,
          category: category,
          mergedInto: target,
        );
        if (alias.text.trim().isNotEmpty) {
          await widget.repository.addAlias(
            alias.text.trim(),
            item.id,
            active: !removeAlias,
          );
        }
      });
    }
    name.dispose();
    alias.dispose();
  }

  Future<void> _addShopping(
    CatalogItem item, {
    int quantity = 1000,
    String unit = 'each',
    bool fast = false,
  }) async {
    final text = TextEditingController(text: '${quantity / 1000}');
    var selectedUnit = unit;
    final confirmed =
        fast ||
        await showDialog<bool>(
              context: context,
              builder: (context) => StatefulBuilder(
                builder: (context, update) => AlertDialog(
                  title: Text('Add ${item.name}'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: text,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: selectedUnit,
                        items: itemUnits
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: (u) => update(() => selectedUnit = u!),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ),
            ) ==
            true;
    if (confirmed) {
      await _run(() async {
        final amount = quantityMilliInput(text.text);
        if (amount == null) {
          throw StateError('Enter a valid positive quantity.');
        }
        await widget.repository.addShopping(
          itemId: item.id,
          name: item.name,
          quantityMilli: amount,
          unit: selectedUnit,
        );
      });
    }
    text.dispose();
  }

  Future<void> _editList(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final d = doc.data();
    var assigned = d['assignedTo'] as String;
    if (!widget.household.members.contains(assigned)) assigned = '';
    var checked = d['checked'] as bool;
    final notes = TextEditingController(text: d['notes'] as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(d['name'] as String),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: checked,
                onChanged: (v) => update(() => checked = v!),
                title: const Text('Checked / bought (does not record payment)'),
              ),
              DropdownButtonFormField<String>(
                initialValue: assigned,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Unassigned')),
                  for (final uid in widget.household.members)
                    DropdownMenuItem(
                      value: uid,
                      child: Text(widget.household.name(uid)),
                    ),
                ],
                onChanged: (v) => update(() => assigned = v!),
              ),
              TextField(
                controller: notes,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(
        () => widget.repository.changeShopping(
          doc.id,
          d['revision'] as int,
          checked: checked,
          assignedTo: assigned,
          notes: notes.text,
        ),
      );
    }
    notes.dispose();
  }

  Future<void> _consume(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final quantity = TextEditingController();
    final operation = widget.repository.collection('stockEvents').doc().id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record consumption'),
        content: TextField(
          controller: quantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity (${doc.data()['unit']})',
            helperText: 'Stock changes only when you confirm.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Consume'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() async {
        final value = quantityMilliInput(quantity.text);
        if (value == null) throw StateError('Enter a valid positive quantity.');
        await widget.repository.consume(doc.id, value, operation);
      });
    }
    quantity.dispose();
  }

  Future<void> _correctPurchase(
    Purchase purchase,
    int revision,
    Map<String, CatalogItem> catalog,
  ) async {
    final quantity = TextEditingController(
      text: purchase.quantityVerified ? '${purchase.quantityMilli / 1000}' : '',
    );
    var unit = purchase.unit, active = purchase.active;
    var classification = purchase.itemId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Review purchase details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: classification,
                decoration: const InputDecoration(labelText: 'Library item'),
                items: catalog.values
                    .map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: (id) => update(() => classification = id!),
              ),
              TextField(
                controller: quantity,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: unit,
                items: itemUnits
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (u) => update(() => unit = u!),
              ),
              CheckboxListTile(
                value: active,
                onChanged: (v) => update(() => active = v!),
                title: const Text('Include in grocery analytics'),
              ),
              const Text(
                'This audited correction does not change the financial expense, delete its receipt details, or alter kitchen stock.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _run(() async {
        final value = quantityMilliInput(quantity.text);
        if (value == null) {
          throw StateError('Enter a positive reviewed quantity.');
        }
        await widget.repository.correctPurchase(
          purchase,
          quantityMilli: value,
          unit: unit,
          active: active,
          expectedRevision: revision,
          itemId: classification,
        );
      });
    }
    quantity.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Grocery tools')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Phase 1 is awaiting verification of the deployed Firestore security rules. Your existing expenses remain available. New grocery data will not be written by this build.',
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Grocery & kitchen'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Library'),
              Tab(text: 'Regular items'),
              Tab(text: 'Shopping'),
              Tab(text: 'Kitchen'),
              Tab(text: 'Prices'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Import historical items',
              onPressed: _busy ? null : _backfill,
              icon: const Icon(Icons.history),
            ),
          ],
        ),
        body: _query(
          _catalog,
          (catalogSnapshot) => _query(
            _purchases,
            (purchaseSnapshot) => _query(
              _shopping,
              (shoppingSnapshot) => _query(
                _stock,
                (stockSnapshot) => _query(
                  _corrections,
                  (correctionSnapshot) => _query(_financial, (
                    financialSnapshot,
                  ) {
                    final voidedIds = financialSnapshot.docs
                        .where((d) => d.data()['voided'] == true)
                        .map((d) => d.id)
                        .toSet();
                    final catalog = {
                      for (final d in catalogSnapshot.docs)
                        d.id: CatalogItem.fromMap(d.id, d.data()),
                    };
                    final correctionMap = {
                      for (final d in correctionSnapshot.docs) d.id: d.data(),
                    };
                    final purchases = purchaseSnapshot.docs
                        .map(
                          (d) => correctPurchaseView(
                            purchaseFromMap(d.id, d.data()),
                            correctionMap[d.id],
                          ),
                        )
                        .map(
                          (p) => voidedIds.contains(p.expenseId)
                              ? correctPurchaseView(p, {
                                  'itemId': p.itemId,
                                  'quantityMilli': p.quantityMilli,
                                  'unit': p.unit,
                                  'quantityVerified': p.quantityVerified,
                                  'active': false,
                                })
                              : p,
                        )
                        .toList();
                    final analytics = analyzePurchases(purchases, catalog);
                    final cached =
                        [
                          catalogSnapshot,
                          purchaseSnapshot,
                          shoppingSnapshot,
                          stockSnapshot,
                          correctionSnapshot,
                          financialSnapshot,
                        ].any(
                          (s) =>
                              s.metadata.isFromCache ||
                              s.metadata.hasPendingWrites,
                        );
                    return Column(
                      children: [
                        if (_busy) const LinearProgressIndicator(),
                        if (cached)
                          const Text(
                            'Cached / pending data — server acceptance not confirmed',
                          ),
                        if (_progress != null) Text(_progress!),
                        Expanded(
                          child: TabBarView(
                            children: [
                              LibraryTab(
                                catalog: catalog,
                                busy: _busy,
                                edit: (item) => _edit(item, catalog),
                                add: (item) => _addShopping(item),
                              ),
                              RegularItemsTab(
                                analytics: analytics,
                                catalog: catalog,
                                currency: widget.household.currency,
                                busy: _busy,
                                add: (item, unit) =>
                                    _addShopping(item, unit: unit, fast: true),
                              ),
                              ShoppingTab(
                                documents: shoppingSnapshot.docs,
                                household: widget.household,
                                busy: _busy,
                                edit: _editList,
                                check: (doc, value) => _run(
                                  () => widget.repository.changeShopping(
                                    doc.id,
                                    doc.data()['revision'] as int,
                                    checked: value,
                                    assignedTo:
                                        widget.household.members.contains(
                                          doc.data()['assignedTo'],
                                        )
                                        ? doc.data()['assignedTo'] as String
                                        : '',
                                    notes: doc.data()['notes'] as String,
                                  ),
                                ),
                              ),
                              KitchenTab(
                                documents: stockSnapshot.docs,
                                catalog: catalog,
                                busy: _busy,
                                consume: _consume,
                                add: (item, unit) =>
                                    _addShopping(item, unit: unit),
                              ),
                              PricesTab(
                                analytics: analytics,
                                catalog: catalog,
                                purchases: purchases,
                                review: (purchase) => _correctPurchase(
                                  purchase,
                                  correctionMap[purchase.id]?['revision']
                                          as int? ??
                                      -1,
                                  catalog,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _query(
    Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    Widget Function(QuerySnapshot<Map<String, dynamic>>) builder,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return RetryMessage(error: snapshot.error!, retry: _reload);
      }
      if (!snapshot.hasData) return const Busy();
      return builder(snapshot.data!);
    },
  );
}

int? quantityMilliInput(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,8}(?:\.\d{1,3})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final result =
      int.parse(parts[0]) * 1000 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(3, '0')));
  return result > 0 && result <= 100000000 ? result : null;
}
