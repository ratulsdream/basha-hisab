import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data.dart';
import '../../widgets/common.dart';
import 'items_domain.dart';

typedef ItemDocument = QueryDocumentSnapshot<Map<String, dynamic>>;

class LibraryTab extends StatelessWidget {
  const LibraryTab({
    super.key,
    required this.catalog,
    required this.busy,
    required this.edit,
    required this.add,
  });
  final Map<String, CatalogItem> catalog;
  final bool busy;
  final void Function(CatalogItem) edit, add;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const ListTile(
        title: Text('Shared item library'),
        subtitle: Text(
          'Aliases are explicit. Package sizes are kept separate. Tap an item to rename, categorize, merge or undo.',
        ),
      ),
      for (final item in catalog.values)
        Card(
          child: ListTile(
            title: Text(item.name),
            subtitle: Text(
              '${item.category}${item.mergedInto.isEmpty ? '' : ' · merged'}',
            ),
            onTap: busy ? null : () => edit(item),
            trailing: IconButton(
              tooltip: 'Add to shopping',
              onPressed: busy ? null : () => add(item),
              icon: const Icon(Icons.add_shopping_cart),
            ),
          ),
        ),
      if (catalog.isEmpty)
        const ListTile(
          title: Text(
            'No items yet. Save a reviewed expense or import historical items.',
          ),
        ),
    ],
  );
}

class RegularItemsTab extends StatelessWidget {
  const RegularItemsTab({
    super.key,
    required this.analytics,
    required this.catalog,
    required this.currency,
    required this.busy,
    required this.add,
  });
  final List<ItemAnalytics> analytics;
  final Map<String, CatalogItem> catalog;
  final String currency;
  final bool busy;
  final void Function(CatalogItem, String) add;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (final stat in analytics)
        Card(
          child: ListTile(
            title: Text(catalog[stat.itemId]?.name ?? stat.itemId),
            subtitle: Text(
              '${stat.frequency} purchases · last ${DateFormat.yMMMd().format(stat.latest.date)} at ${stat.latest.merchant}\nSpent ${displayMoney(currency, stat.expenditure)}\nKnown quantity: ${stat.purchases.where((p) => p.quantityVerified).fold<int>(0, (acc, p) => acc + p.quantityMilli) / 1000} ${stat.unit}\nLatest unit price: ${stat.latest.quantityVerified ? stat.latest.unitPrice.toStringAsFixed(2) : 'unknown'} cents/${stat.unit}\nAverage unit price: ${stat.averageUnitPrice?.toStringAsFixed(2) ?? 'unknown'} cents/${stat.unit}',
            ),
            trailing: IconButton(
              tooltip: 'Add suggested item to shopping',
              onPressed: busy || catalog[stat.itemId] == null
                  ? null
                  : () => add(catalog[stat.itemId]!, stat.unit),
              icon: const Icon(Icons.add_shopping_cart),
            ),
          ),
        ),
    ],
  );
}

class ShoppingTab extends StatelessWidget {
  const ShoppingTab({
    super.key,
    required this.documents,
    required this.household,
    required this.busy,
    required this.edit,
    required this.check,
  });
  final List<ItemDocument> documents;
  final Household household;
  final bool busy;
  final void Function(ItemDocument) edit;
  final void Function(ItemDocument, bool) check;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const ListTile(
        title: Text('Shared shopping list'),
        subtitle: Text(
          'Add from Library or Regular items. Checking an item never records an expense or changes stock.',
        ),
      ),
      for (final doc in documents)
        CheckboxListTile(
          value: doc.data()['checked'] as bool,
          onChanged: busy ? null : (value) => check(doc, value!),
          title: Text(
            '${doc.data()['name']} · ${(doc.data()['quantityMilli'] as int) / 1000} ${doc.data()['unit']}',
          ),
          subtitle: InkWell(
            onTap: busy ? null : () => edit(doc),
            child: Text(
              '${doc.data()['notes']} · ${(doc.data()['assignedTo'] as String).isEmpty ? 'Unassigned' : household.name(doc.data()['assignedTo'] as String)} · tap to edit',
            ),
          ),
        ),
    ],
  );
}

class KitchenTab extends StatelessWidget {
  const KitchenTab({
    super.key,
    required this.documents,
    required this.catalog,
    required this.busy,
    required this.consume,
    required this.add,
  });
  final List<ItemDocument> documents;
  final Map<String, CatalogItem> catalog;
  final bool busy;
  final void Function(ItemDocument) consume;
  final void Function(CatalogItem, String) add;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const ListTile(
        title: Text('Kitchen inventory'),
        subtitle: Text(
          'Restock from a saved receipt’s details after review. Consumption is always manual.',
        ),
      ),
      for (final doc in documents) _lot(doc),
    ],
  );
  Widget _lot(ItemDocument doc) {
    final row = doc.data(),
        item = catalog[resolveItem(doc.data()['itemId'] as String, catalog)];
    final expiry = (row['expiry'] as Timestamp?)?.toDate();
    return Card(
      child: ListTile(
        title: Text(
          '${row['name']} · ${(row['quantityMilli'] as int) / 1000} ${row['unit']}',
        ),
        subtitle: Text(
          '${(row['quantityMilli'] as int) <= (row['lowStockMilli'] as int) ? 'Low stock · ' : ''}${expiry == null ? 'No expiry' : DateFormat.yMMMd().format(expiry)}${expiry != null && expiry.isBefore(DateTime.now()) ? ' · check expiry' : ''}',
        ),
        onTap: busy ? null : () => consume(doc),
        trailing: IconButton(
          tooltip: 'Add low stock to shopping',
          onPressed: busy || item == null
              ? null
              : () => add(item, row['unit'] as String),
          icon: const Icon(Icons.add_shopping_cart),
        ),
      ),
    );
  }
}

class PricesTab extends StatelessWidget {
  const PricesTab({
    super.key,
    required this.analytics,
    required this.catalog,
    required this.purchases,
    required this.review,
  });
  final List<ItemAnalytics> analytics;
  final Map<String, CatalogItem> catalog;
  final List<Purchase> purchases;
  final void Function(Purchase) review;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const ListTile(
        title: Text('Comparable price history'),
        subtitle: Text(
          'Only reviewed quantities with matching units are compared. Tap a purchase to review quantities or exclude/restore it in grocery analytics. Financial expenses and stock stay unchanged.',
        ),
      ),
      for (final purchase in purchases)
        ListTile(
          title: Text(purchase.name),
          subtitle: Text(
            purchase.active
                ? (purchase.quantityVerified
                      ? '${purchase.quantityMilli / 1000} ${purchase.unit}'
                      : 'Quantity unknown — tap to review')
                : 'Excluded from grocery analytics — tap to restore',
          ),
          onTap: () => review(purchase),
        ),
      for (final stat in analytics) ...[
        ListTile(
          title: Text(
            '${catalog[stat.itemId]?.name ?? stat.itemId} / ${stat.unit}',
          ),
          subtitle: Text(
            'Movement: ${stat.priceMovement?.toStringAsFixed(2) ?? 'not enough comparable prices'} cents/unit',
          ),
        ),
        for (final purchase
            in ([...stat.purchases]..sort((a, b) => b.date.compareTo(a.date)))
                .where((p) => p.quantityVerified))
          ListTile(
            title: Text(
              '${purchase.merchant} · ${DateFormat.yMMMd().format(purchase.date)}',
            ),
            subtitle: Text(
              '${purchase.quantityMilli / 1000} ${purchase.unit} · ${purchase.unitPrice.toStringAsFixed(2)} cents/unit',
            ),
          ),
      ],
    ],
  );
}
