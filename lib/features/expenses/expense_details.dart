import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data.dart';
import '../items/items_repository.dart';
import '../items/restock_screen.dart';

import '../../widgets/common.dart';

class ExpenseDetails extends StatefulWidget {
  const ExpenseDetails({
    super.key,
    required this.expense,
    required this.household,
    required this.repository,
  });
  final Expense expense;
  final Household household;
  final HouseholdRepository repository;
  @override
  State<ExpenseDetails> createState() => _ExpenseDetailsState();
}

class _ExpenseDetailsState extends State<ExpenseDetails> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _watchItems() => widget
      .repository
      .db
      .collection('households')
      .doc(widget.household.id)
      .collection('expenses')
      .doc(widget.expense.id)
      .collection('items')
      .orderBy('index')
      .snapshots();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _items = _watchItems();
  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final household = widget.household;
    return Scaffold(
      appBar: AppBar(title: const Text('Expense details')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            expense.merchant,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(DateFormat.yMMMMd().format(expense.date)),
          Text('Paid by ${household.name(expense.payer)}'),
          Text('Added by ${household.name(expense.creator)}'),
          if (widget.repository.enableItemIntelligence && expense.itemCount > 0)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RestockScreen(
                    repository: ItemsRepository(
                      widget.repository.db,
                      widget.repository.uid,
                      household.id,
                    ),
                    expenseId: expense.id,
                  ),
                ),
              ),
              icon: const Icon(Icons.kitchen),
              label: const Text('Review kitchen restock'),
            ),
          const Divider(height: 32),
          if (expense.itemCount == 0)
            const Text('No item breakdown was added.')
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _items,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return RetryMessage(
                    error: snapshot.error!,
                    retry: () => setState(() => _items = _watchItems()),
                  );
                }
                if (!snapshot.hasData) {
                  return const Busy(message: 'Loading items…');
                }
                if (snapshot.data!.docs.length != expense.itemCount) {
                  return const Text(
                    'Item details are incomplete. Reconnect to load all items.',
                  );
                }
                return Column(
                  children: [
                    for (final item in snapshot.data!.docs)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.data()['name'] as String),
                        trailing: Text(
                          displayMoney(
                            household.currency,
                            item.data()['amount'] as int,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          const Divider(height: 32),
          Text(
            'Total: ${displayMoney(household.currency, expense.total)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}
