import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data.dart';
import '../../domain.dart';
import '../../widgets/common.dart';
import 'planning_domain.dart';

typedef FinanceDocument = QueryDocumentSnapshot<Map<String, dynamic>>;

class ReportsTab extends StatelessWidget {
  const ReportsTab({
    super.key,
    required this.expenses,
    required this.previous,
    required this.budget,
    required this.currency,
    required this.editBudget,
  });
  final List<FinanceEntry> expenses, previous;
  final Map<String, dynamic>? budget;
  final String currency;
  final VoidCallback editBudget;
  @override
  Widget build(BuildContext context) {
    final totals = categoryTotals(expenses),
        spent = totals.values.fold<int>(0, (acc, n) => acc + n),
        before = categoryTotals(
          previous,
        ).values.fold<int>(0, (acc, n) => acc + n),
        limit = budget?['total'] as int? ?? 0;
    final categories = Map<String, dynamic>.from(
      budget?['categories'] as Map? ?? {},
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: Text('Household spending: ${displayMoney(currency, spent)}'),
            subtitle: Text(
              'Change from previous month: ${displayMoney(currency, spent - before)}\nRepayments and private expenses are excluded.',
            ),
          ),
        ),
        OutlinedButton(
          onPressed: editBudget,
          child: const Text('Set monthly/category budgets'),
        ),
        if (limit > 0)
          Card(
            child: ListTile(
              title: Text(
                spent > limit
                    ? 'Over budget by ${displayMoney(currency, spent - limit)}'
                    : 'Remaining ${displayMoney(currency, limit - spent)}',
              ),
              subtitle: Text(
                'Budget ${displayMoney(currency, limit)}${spent >= limit * 0.8 ? ' · approaching / above threshold' : ''}',
              ),
            ),
          ),
        for (final category in expenseCategories)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$category · ${displayMoney(currency, totals[category]!)}${categories[category] == null ? '' : ' / ${displayMoney(currency, categories[category] as int)}'}',
                ),
                LinearProgressIndicator(
                  value: spent <= 0
                      ? 0
                      : (totals[category]! / spent).clamp(0, 1),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class PaymentsTab extends StatelessWidget {
  const PaymentsTab({
    super.key,
    required this.payments,
    required this.settlement,
    required this.home,
    required this.add,
    required this.reverse,
  });
  final List<Repayment> payments;
  final GroupSettlement settlement;
  final Household home;
  final VoidCallback add;
  final void Function(Repayment) reverse;
  @override
  Widget build(BuildContext context) {
    final reversed = payments
        .where((p) => p.reversalOf.isNotEmpty)
        .map((p) => p.reversalOf)
        .toSet();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Repayments are transfers, not spending. Balances here apply only to the selected month.',
        ),
        for (final due in settlement.transfers)
          Card(
            child: ListTile(
              title: Text(
                '${home.name(due.debtor)} owes ${home.name(due.creditor)} ${displayMoney(home.currency, due.amount)}',
              ),
            ),
          ),
        if (settlement.transfers.isEmpty)
          const ListTile(title: Text('No remaining recorded dues.')),
        FilledButton(
          onPressed: add,
          child: const Text('Record partial/full repayment'),
        ),
        for (final p in payments)
          ListTile(
            title: Text(
              '${p.reversalOf.isEmpty ? 'Payment' : 'Reversal'} · ${displayMoney(home.currency, p.amount)}',
            ),
            subtitle: Text(
              '${home.name(p.from)} → ${home.name(p.to)} · ${DateFormat.yMMMd().format(p.date)}\n${p.reference}',
            ),
            trailing: p.reversalOf.isEmpty && !reversed.contains(p.id)
                ? TextButton(
                    onPressed: () => reverse(p),
                    child: const Text('Reverse'),
                  )
                : null,
          ),
      ],
    );
  }
}

class RecurringTab extends StatelessWidget {
  const RecurringTab({
    super.key,
    required this.templates,
    required this.month,
    required this.currency,
    required this.edit,
    required this.confirm,
  });
  final List<FinanceDocument> templates;
  final DateTime month;
  final String currency;
  final void Function(FinanceDocument?) edit;
  final void Function(FinanceDocument) confirm;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Templates remind you; they never silently create expenses. Confirm each occurrence.',
      ),
      FilledButton(
        onPressed: () => edit(null),
        child: const Text('Add recurring template'),
      ),
      for (final t in templates)
        Card(
          child: ListTile(
            title: Text(
              '${t.data()['merchant']} · ${displayMoney(currency, t.data()['amount'] as int)}',
            ),
            subtitle: Text(
              '${t.data()['enabled'] == true ? 'Enabled' : 'Disabled'} · ${DateFormat.yMMMd().format(recurringDate(month, t.data()['day'] as int))}',
            ),
            onTap: () => edit(t),
            trailing: TextButton(
              onPressed: t.data()['enabled'] == true ? () => confirm(t) : null,
              child: const Text('Confirm month'),
            ),
          ),
        ),
    ],
  );
}

class SearchTab extends StatelessWidget {
  const SearchTab({
    super.key,
    required this.results,
    required this.currency,
    required this.search,
  });
  final List<FinanceEntry>? results;
  final String currency;
  final VoidCallback search;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Search the selected group by date, merchant, Greek/English item, category, payer and amount. Change the group filter from the top bar.',
      ),
      FilledButton(onPressed: search, child: const Text('Search / filters')),
      if (results != null && results!.isEmpty)
        const ListTile(title: Text('No matching expenses')),
      for (final e in results ?? <FinanceEntry>[])
        ListTile(
          title: Text('${e.personal ? 'Private · ' : ''}${e.merchant}'),
          subtitle: Text(
            '${DateFormat.yMMMd().format(e.date)} · ${e.category}',
          ),
          trailing: Text(displayMoney(currency, e.signedAmount)),
        ),
    ],
  );
}

class PersonalTab extends StatelessWidget {
  const PersonalTab({super.key, required this.entries, required this.currency});
  final List<FinanceEntry> entries;
  final String currency;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Only your account can read these entries. They never enter household spending, shared items or settlement. Add one from Add expense → Personal expense.',
      ),
      ListTile(
        title: Text(
          'Your personal spending: ${displayMoney(currency, entries.where((e) => !e.voided).fold<int>(0, (acc, e) => acc + e.signedAmount))}',
        ),
      ),
      for (final e in entries)
        ListTile(
          title: Text(e.merchant),
          subtitle: Text(
            '${DateFormat.yMMMd().format(e.date)} · ${e.category}',
          ),
          trailing: Text(displayMoney(currency, e.signedAmount)),
        ),
    ],
  );
}

class CorrectionsTab extends StatelessWidget {
  const CorrectionsTab({
    super.key,
    required this.documents,
    required this.amend,
  });
  final List<FinanceDocument> documents;
  final void Function(FinanceDocument) amend;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Correct categories or void/restore your own expense. Original amounts and item records remain intact; every change is audited.',
      ),
      for (final doc in documents)
        ListTile(
          title: Text(doc.data()['merchant'] as String),
          subtitle: Text(
            '${doc.data()['category'] ?? 'uncategorized'} · ${doc.data()['voided'] == true ? 'Voided' : 'Active'}',
          ),
          onTap: () => amend(doc),
        ),
    ],
  );
}
