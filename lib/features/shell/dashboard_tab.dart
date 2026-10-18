import 'draft_status.dart';
import 'regular_preview.dart';
import '../items/items_repository.dart';
import '../../widgets/common.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data.dart';
import '../../domain.dart';
import '../../l10n/app_text.dart';
import '../expenses/expense_details.dart';
import '../planning/planning_domain.dart';
import '../planning/planning_repository.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({
    super.key,
    required this.repository,
    required this.home,
    required this.scan,
    required this.add,
    required this.shopping,
    required this.history,
    required this.regular,
    required this.budget,
    required this.invite,
    required this.pending,
  });
  final HouseholdRepository repository;
  final Household home;
  final VoidCallback scan,
      add,
      shopping,
      history,
      regular,
      budget,
      invite,
      pending;
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  late final month = DateTime(DateTime.now().year, DateTime.now().month);
  late Stream<QuerySnapshot<Map<String, dynamic>>> expenses = widget.repository
      .watchExpenses(widget.home.id, month);
  late final payments = widget.repository.db
      .collection('households')
      .doc(widget.home.id)
      .collection('payments')
      .where('month', isEqualTo: monthKey(month))
      .snapshots(includeMetadataChanges: true);
  late final budget = widget.repository.db
      .collection('households')
      .doc(widget.home.id)
      .collection('budgets')
      .doc(monthKey(month))
      .snapshots(includeMetadataChanges: true);
  late final shopping = widget.repository.db
      .collection('households')
      .doc(widget.home.id)
      .collection('shopping')
      .where('checked', isEqualTo: false)
      .limit(4)
      .snapshots(includeMetadataChanges: true);
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: expenses,
    builder: (context, s) {
      if (s.hasError) {
        return _SectionError(
          retry: () => setState(
            () => expenses = widget.repository.watchExpenses(
              widget.home.id,
              month,
            ),
          ),
        );
      }
      if (!s.hasData) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading expenses'),
        );
      }
      final rows =
          s.data!.docs
              .map((d) => Expense(d.id, d.data()))
              .where((e) => !e.voided)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.repository.enableItemIntelligence ? payments : null,
        builder: (context, p) {
          final settlement = financeSettlement(
            widget.home.members,
            widget.home.legacyMembers,
            rows.map(
              (e) => FinanceEntry(
                id: e.id,
                merchant: e.merchant,
                payer: e.payer,
                date: e.date,
                amount: e.total,
                refund: e.refund,
                category: e.category,
                splits: e.splits,
                members: e.splitBetween,
              ),
            ),
            p.data?.docs.map((d) => paymentFromMap(d.id, d.data())) ?? [],
          );
          final colors = Theme.of(context).colorScheme;
          final uid = widget.repository.uid;
          final peerPaid = settlement.paid.entries
              .where((e) => e.key != uid)
              .fold<int>(0, (v, e) => v + e.value);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                DateFormat.yMMMM(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Card(
                color: colors.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText('Household spending'),
                      const SizedBox(height: 8),
                      Text(
                        displayMoney(widget.home.currency, settlement.total),
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.onPrimaryContainer,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const AppText('This month'),
                    ],
                  ),
                ),
              ),
              if (s.data!.metadata.isFromCache ||
                  s.data!.metadata.hasPendingWrites ||
                  (p.data?.metadata.isFromCache ?? false))
                const _Notice(
                  icon: Icons.cloud_off_outlined,
                  text:
                      'Local data — totals may be incomplete until connected.',
                ),
              if (widget.repository.enableItemIntelligence)
                DraftStatus(uid: uid, open: widget.pending),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: widget.scan,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const AppText('Scan Receipt'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.add,
                    icon: const Icon(Icons.add),
                    label: const AppText('Add Expense'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.shopping,
                    icon: const Icon(Icons.shopping_basket_outlined),
                    label: const AppText('Shopping List'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final metric in [
                      ('My contribution', settlement.paid[uid] ?? 0),
                      ('Roommate contribution', peerPaid),
                      ('My share', settlement.shares[uid] ?? 0),
                    ])
                      SizedBox(
                        width: c.maxWidth < 360
                            ? c.maxWidth
                            : (c.maxWidth - 12) / 2,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(metric.$1),
                                const SizedBox(height: 8),
                                Text(
                                  displayMoney(widget.home.currency, metric.$2),
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _heading('Settlement'),
              if (widget.repository.enableItemIntelligence &&
                  (p.hasError || !p.hasData))
                _Notice(
                  icon: Icons.sync,
                  text: p.hasError
                      ? 'Could not load settlement. Retry without losing your expenses.'
                      : 'Settlement is updating.',
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.repository.enableItemIntelligence)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: AppText(
                              'Shared-expense balance; repayments need verified access.',
                            ),
                          ),

                        if (widget.home.members.length < 2 &&
                            settlement.transfers.isEmpty)
                          const AppText('Waiting for roommate')
                        else if (settlement.transfers.isEmpty)
                          const AppText('All square — no one owes anything.')
                        else
                          for (final t in settlement.transfers)
                            Text(
                              Localizations.localeOf(context).languageCode ==
                                      'bn'
                                  ? '${widget.home.name(t.debtor)} দেবেন ${widget.home.name(t.creditor)}-কে ${displayMoney(widget.home.currency, t.amount)}'
                                  : '${widget.home.name(t.debtor)} owes ${widget.home.name(t.creditor)} ${displayMoney(widget.home.currency, t.amount)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                        if (widget.home.members.length == 1)
                          TextButton.icon(
                            onPressed: widget.invite,
                            icon: const Icon(Icons.person_add_outlined),
                            label: const AppText('Invite roommate'),
                          ),
                      ],
                    ),
                  ),
                ),
              _heading('Monthly budget', action: widget.budget),
              if (!widget.repository.enableItemIntelligence)
                _locked('Budget settings', widget.budget)
              else
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: budget,
                  builder: (context, b) {
                    if (b.hasError) {
                      return _locked(
                        'Could not load this section.',
                        widget.budget,
                      );
                    }
                    if (!b.hasData) return const LinearProgressIndicator();
                    final total = b.data!.data()?['total'] as int?;
                    if (total == null) {
                      return _locked('Set a budget', widget.budget);
                    }
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayMoney(widget.home.currency, total),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: total > 0
                                  ? (settlement.total / total).clamp(0, 1)
                                  : 0,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${tr(context, total >= settlement.total ? 'Remaining' : 'Over budget')}: ${displayMoney(widget.home.currency, (total - settlement.total).abs())}',
                            ),
                            if (b.data!.metadata.isFromCache)
                              const AppText(
                                'Local data — totals may be incomplete until connected.',
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              _heading('Recent expenses', action: widget.history),
              if (rows.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_outlined),
                    title: AppText('No expenses this month.'),
                    subtitle: AppText(
                      'Add your first expense or scan a receipt.',
                    ),
                  ),
                ),
              for (final e in rows.take(4))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(e.merchant),
                    subtitle: Text(
                      '${DateFormat.MMMd().format(e.date)} · ${widget.home.name(e.payer)}',
                    ),
                    trailing: Text(
                      displayMoney(
                        widget.home.currency,
                        e.refund ? -e.total : e.total,
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExpenseDetails(
                          expense: e,
                          household: widget.home,
                          repository: widget.repository,
                        ),
                      ),
                    ),
                  ),
                ),
              _heading('Regular items', action: widget.regular),
              if (!widget.repository.enableItemIntelligence)
                _locked('Verified access required', widget.regular)
              else
                RegularPreview(
                  repository: ItemsRepository(
                    widget.repository.db,
                    widget.repository.uid,
                    widget.home.id,
                  ),
                  open: widget.regular,
                ),
              _heading('Pending shopping items', action: widget.shopping),
              if (!widget.repository.enableItemIntelligence)
                _locked('Verified access required', widget.shopping)
              else
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: shopping,
                  builder: (context, q) {
                    if (q.hasError) {
                      return _locked(
                        'Could not load this section.',
                        widget.shopping,
                      );
                    }
                    if (!q.hasData) return const LinearProgressIndicator();
                    if (q.data!.docs.isEmpty) {
                      return const Card(
                        child: ListTile(
                          title: AppText('Your shopping list is clear.'),
                          subtitle: AppText(
                            'Add items before your next shopping trip.',
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final d in q.data!.docs)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.radio_button_unchecked),
                              title: Text(d.data()['name'] as String),
                              onTap: widget.shopping,
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          );
        },
      );
    },
  );
  Widget _heading(String title, {VoidCallback? action}) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: AppText(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          TextButton(onPressed: action, child: const AppText('See all')),
      ],
    ),
  );
  Widget _locked(String text, VoidCallback tap) => Card(
    child: ListTile(
      leading: const Icon(Icons.lock_outline),
      title: AppText(text),
      subtitle: const AppText('Security review needed'),
      onTap: tap,
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(leading: Icon(icon), title: AppText(text)),
  );
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.retry});
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppText('Could not load this section.'),
        TextButton(onPressed: retry, child: const AppText('Retry')),
      ],
    ),
  );
}
