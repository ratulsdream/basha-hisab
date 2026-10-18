import 'package:basha_hisab/l10n/app_text.dart';
import 'package:flutter/material.dart';
import '../../widgets/common.dart';
import 'items_domain.dart';
import 'items_repository.dart';
import 'items_screen.dart' show quantityMilliInput;

class RestockScreen extends StatefulWidget {
  const RestockScreen({
    super.key,
    required this.repository,
    required this.expenseId,
  });
  final ItemsRepository repository;
  final String expenseId;
  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockRow {
  _RestockRow(this.purchase)
    : quantity = TextEditingController(
        text: purchase.quantityVerified
            ? '${purchase.quantityMilli / 1000}'
            : '',
      ),
      unit = purchase.unit;
  final Purchase purchase;
  final TextEditingController quantity;
  bool selected = false;
  String unit;
  DateTime? expiry;
}

class _RestockScreenState extends State<RestockScreen> {
  final rows = <_RestockRow>[];
  bool busy = true;
  Object? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.repository.indexExpense(widget.expenseId);
      final snapshot = await widget.repository
          .collection('purchases')
          .where('expenseId', isEqualTo: widget.expenseId)
          .get();
      rows.addAll(
        snapshot.docs.map((d) => _RestockRow(purchaseFromMap(d.id, d.data()))),
      );
    } catch (e) {
      error = e;
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    for (final row in rows) {
      row.quantity.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (busy) return;
    final chosen = rows.where((r) => r.selected).toList();
    if (chosen.isEmpty) {
      showError(context, StateError('Select at least one item to restock.'));
      return;
    }
    for (final row in chosen) {
      if (quantityMilliInput(row.quantity.text) == null) {
        showError(
          context,
          StateError('Review the quantity for ${row.purchase.name}.'),
        );
        return;
      }
    }
    setState(() => busy = true);
    try {
      for (final row in chosen) {
        await widget.repository.restock(
          row.purchase,
          quantityMilli: quantityMilliInput(row.quantity.text)!,
          unit: row.unit,
          expiry: row.expiry,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review kitchen restock')),
    body: error != null
        ? RetryMessage(
            error: error!,
            retry: () {
              setState(() {
                error = null;
                busy = true;
              });
              _load();
            },
          )
        : busy && rows.isEmpty
        ? const Busy()
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Only selected items enter stock. Review quantities, units and optional expiry. No consumption is inferred. Repeating a confirmed restock never adds it twice.',
              ),
              for (final row in rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: row.selected,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => row.selected = v!),
                          title: Text(row.purchase.name),
                        ),
                        TextField(
                          controller: row.quantity,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: tr(context, 'Quantity'),
                            helperText: row.purchase.quantityVerified
                                ? null
                                : 'Not known from receipt — enter the amount added to stock',
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: row.unit,
                          items: itemUnits
                              .map(
                                (u) =>
                                    DropdownMenuItem(value: u, child: Text(u)),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (u) => setState(() => row.unit = u!),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                    initialDate: row.expiry ?? DateTime.now(),
                                  );
                                  if (mounted && date != null) {
                                    setState(() => row.expiry = date);
                                  }
                                },
                          child: Text(
                            row.expiry == null
                                ? 'Optional expiry date'
                                : 'Expiry: ${row.expiry!.toIso8601String().split('T').first}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              FilledButton(
                onPressed: busy ? null : _save,
                child: Text(busy ? 'Saving…' : 'Confirm selected restock'),
              ),
            ],
          ),
  );
}
