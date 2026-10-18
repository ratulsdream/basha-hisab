import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_text.dart';
import '../items/items_domain.dart';
import '../items/items_repository.dart';

/// Uses the same reviewed corrections, merge graph and void filtering as Items.
class RegularPreview extends StatefulWidget {
  const RegularPreview({
    super.key,
    required this.repository,
    required this.open,
  });
  final ItemsRepository repository;
  final VoidCallback open;
  @override
  State<RegularPreview> createState() => _RegularPreviewState();
}

class _RegularPreviewState extends State<RegularPreview> {
  late final streams = [
    for (final path in [
      'catalog',
      'purchases',
      'purchaseCorrections',
      'expenses',
    ])
      widget.repository.watch(path),
  ];
  Widget query(int i, List<QuerySnapshot<Map<String, dynamic>>> values) {
    if (i < streams.length) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: streams[i],
        builder: (context, s) {
          if (s.hasError) {
            return Card(
              child: ListTile(
                title: const AppText('Could not load this section.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.open,
              ),
            );
          }
          if (!s.hasData) return const LinearProgressIndicator();
          return query(i + 1, [...values, s.data!]);
        },
      );
    }
    final catalog = {
      for (final d in values[0].docs) d.id: CatalogItem.fromMap(d.id, d.data()),
    };
    final corrections = {for (final d in values[2].docs) d.id: d.data()};
    final voided = values[3].docs
        .where((d) => d.data()['voided'] == true)
        .map((d) => d.id)
        .toSet();
    final events = values[1].docs
        .map(
          (d) => correctPurchaseView(
            purchaseFromMap(d.id, d.data()),
            corrections[d.id],
          ),
        )
        .where((p) => !voided.contains(p.expenseId));
    final rows =
        analyzePurchases(
            events,
            catalog,
          ).where((r) => r.frequency >= 2).toList()
          ..sort((a, b) => b.frequency.compareTo(a.frequency));
    if (rows.isEmpty) {
      return const Card(
        child: ListTile(
          title: AppText('No regular items yet.'),
          subtitle: AppText('Your repeated purchases will appear here.'),
        ),
      );
    }
    return Column(
      children: [
        if (values.any(
          (v) => v.metadata.isFromCache || v.metadata.hasPendingWrites,
        ))
          const AppText(
            'Local data — totals may be incomplete until connected.',
          ),
        for (final row in rows.take(3))
          Card(
            child: ListTile(
              leading: const Icon(Icons.repeat),
              title: Text(catalog[row.itemId]?.name ?? row.latest.name),
              trailing: Text('${row.frequency}×'),
              onTap: widget.open,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => query(0, []);
}
