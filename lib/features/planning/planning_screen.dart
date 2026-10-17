import '../exports/export_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data.dart';
import '../../domain.dart';
import '../../widgets/common.dart';
import 'planning_domain.dart';
import 'planning_repository.dart';
import 'form_dialog.dart';
import 'planning_tabs.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({
    super.key,
    required this.repository,
    required this.household,
  });
  final HouseholdRepository repository;
  final Household household;
  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  late final repo = PlanningRepository(
    widget.repository.db,
    widget.repository.uid,
    widget.household.id,
  );
  late Stream<QuerySnapshot<Map<String, dynamic>>> _expenses = repo.watch(
        'expenses',
      ),
      _payments = repo.watch('payments'),
      _budgets = repo.watch('budgets'),
      _templates = repo.watch('recurring'),
      _personal = widget.repository.profile
          .collection('personalExpenses')
          .where('groupId', isEqualTo: widget.household.id)
          .snapshots(includeMetadataChanges: true);
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool busy = false;
  List<FinanceEntry>? searchResults;
  void _reload() => setState(() {
    _expenses = repo.watch('expenses');
    _payments = repo.watch('payments');
    _budgets = repo.watch('budgets');
    _templates = repo.watch('recurring');
    _personal = widget.repository.profile
        .collection('personalExpenses')
        .where('groupId', isEqualTo: widget.household.id)
        .snapshots(includeMetadataChanges: true);
  });
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _budget(Map<String, dynamic>? current) async {
    final prior = Map<String, dynamic>.from(
      current?['categories'] as Map? ?? {},
    );
    final values = await financeForm(context, 'Monthly budget', [
      FinanceField(
        'total',
        'Group monthly budget (${widget.household.currency})',
        initial: moneyInput(current?['total'] as int? ?? 0),
        money: true,
        required: true,
      ),
      for (final category in expenseCategories)
        FinanceField(
          category,
          '$category budget (optional)',
          initial: prior[category] == null
              ? ''
              : moneyInput(prior[category] as int),
          money: true,
        ),
    ]);
    if (values == null) return;
    await run(
      () => repo.setBudget(
        monthKey(month),
        parseMoney(values['total']!)!,
        {
          for (final c in expenseCategories)
            if (values[c]!.isNotEmpty) c: parseMoney(values[c]!)!,
        },
        current?['revision'] as int? ?? -1,
      ),
    );
  }

  Future<void> _payment(
    List<Repayment> payments,
    List<FinanceEntry> expenses,
  ) async {
    final settle = financeSettlement(
      widget.household.members,
      widget.household.legacyMembers,
      expenses,
      payments,
    );
    final due = settle.transfers.firstOrNull;
    final names = widget.household.names;
    final values =
        await financeForm(context, 'Record repayment (not spending)', [
          FinanceField(
            'from',
            'Paid by',
            initial: due?.debtor ?? widget.repository.uid,
            choices: names,
          ),
          FinanceField(
            'to',
            'Paid to',
            initial:
                due?.creditor ??
                names.keys.firstWhere(
                  (id) => id != widget.repository.uid,
                  orElse: () => widget.repository.uid,
                ),
            choices: names,
          ),
          FinanceField(
            'amount',
            'Amount (${widget.household.currency})',
            initial: moneyInput(due?.amount ?? 0),
            money: true,
            positive: true,
            required: true,
          ),
          FinanceField(
            'date',
            'Effective date',
            initial: DateTime(
              month.year,
              month.month,
              month.month == DateTime.now().month ? DateTime.now().day : 1,
            ).toIso8601String().split('T').first,
            date: true,
            required: true,
          ),
          FinanceField('reference', 'Payment receipt/reference (optional)'),
        ]);
    if (values == null) return;
    final id = repo.collection('payments').doc().id;
    await run(
      () => repo.recordPayment(
        id: id,
        from: values['from']!,
        to: values['to']!,
        amount: parseMoney(values['amount']!)!,
        date: DateTime.parse(values['date']!),
        reference: values['reference']!,
      ),
    );
  }

  Future<void> _reverse(Repayment payment) async {
    final values = await financeForm(context, 'Reverse recorded payment', [
      const FinanceField(
        'reason',
        'Reason (kept in audit history)',
        required: true,
      ),
    ]);
    if (values == null) return;
    await run(
      () => repo.recordPayment(
        id: 'reverse_${payment.id}',
        from: payment.from,
        to: payment.to,
        amount: payment.amount,
        date: payment.date,
        reference: values['reason']!,
        reversalOf: payment.id,
      ),
    );
  }

  Future<void> _template(
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  ) async {
    final d = doc?.data();
    final active = {
      for (final id in widget.household.members) id: widget.household.name(id),
    };
    final values = await financeForm(context, 'Recurring expense template', [
      FinanceField(
        'merchant',
        'Bill / merchant',
        initial: d?['merchant'] as String? ?? '',
        required: true,
      ),
      FinanceField(
        'amount',
        'Amount',
        initial: d == null ? '' : moneyInput(d['amount'] as int),
        required: true,
        money: true,
        positive: true,
      ),
      FinanceField(
        'payer',
        'Payer',
        initial: d?['payer'] as String? ?? widget.repository.uid,
        choices: active,
      ),
      FinanceField(
        'category',
        'Category',
        initial: d?['category'] as String? ?? 'utilities',
        choices: {for (final c in expenseCategories) c: c},
      ),
      FinanceField(
        'day',
        'Day of month (1–31)',
        initial: '${d?['day'] ?? 1}',
        integer: true,
        required: true,
      ),
      FinanceField(
        'enabled',
        'Reminders enabled',
        initial: '${d?['enabled'] ?? true}',
        flag: true,
      ),
    ]);
    if (values == null) return;
    await run(
      () => repo.saveTemplate(
        id: doc?.id ?? repo.collection('recurring').doc().id,
        merchant: values['merchant']!,
        amount: parseMoney(values['amount']!)!,
        payer: values['payer']!,
        category: values['category']!,
        day: int.parse(values['day']!),
        enabled: values['enabled'] == 'true',
        expectedRevision: d?['revision'] as int? ?? -1,
      ),
    );
  }

  Future<void> _confirmTemplate(
    QueryDocumentSnapshot<Map<String, dynamic>> template,
  ) async {
    final d = template.data();
    if (d['enabled'] != true) return;
    final date = recurringDate(month, d['day'] as int);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm this occurrence'),
        content: Text(
          '${d['merchant']}\n${displayMoney(widget.household.currency, d['amount'] as int)}\n${DateFormat.yMMMd().format(date)}\nNo expense is created until you confirm. A second confirmation cannot create a duplicate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create expense'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await run(
      () => widget.repository.savePlannedExpense(
        household: widget.household,
        id: occurrenceId(template.id, month),
        merchant: d['merchant'] as String,
        payer: d['payer'] as String,
        date: date,
        items: const [],
        total: d['amount'] as int,
        category: d['category'] as String,
        recurringId: template.id,
      ),
    );
  }

  Future<void> _amend(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final row = doc.data();
    final values = await financeForm(context, 'Correct expense metadata', [
      FinanceField(
        'category',
        'Category',
        initial: row['category'] as String? ?? 'uncategorized',
        choices: {for (final c in expenseCategories) c: c},
      ),
      FinanceField(
        'voided',
        'Exclude expense (original and audit retained)',
        initial: '${row['voided'] ?? false}',
        flag: true,
        readOnly: row['createdBy'] != widget.repository.uid,
      ),
    ]);
    if (values == null) return;
    await run(
      () => repo.amendExpense(
        doc.id,
        category: values['category']!,
        voided: values['voided'] == 'true',
        expectedRevision: row['revision'] as int? ?? -1,
      ),
    );
  }

  Future<void> _search() async {
    final values = await financeForm(
      context,
      'Search ${widget.household.title}',
      [
        const FinanceField('text', 'Merchant or item (Greek/English)'),
        FinanceField(
          'start',
          'From date',
          initial: month.toIso8601String().split('T').first,
          date: true,
        ),
        FinanceField(
          'end',
          'Through date',
          initial: DateTime(
            month.year,
            month.month + 1,
            0,
          ).toIso8601String().split('T').first,
          date: true,
        ),
        FinanceField(
          'category',
          'Category',
          choices: {'': 'All', for (final c in expenseCategories) c: c},
        ),
        FinanceField(
          'payer',
          'Payer',
          choices: {'': 'Anyone', ...widget.household.names},
        ),
        const FinanceField('min', 'Minimum amount', money: true),
        const FinanceField('max', 'Maximum amount', money: true),
        const FinanceField(
          'personal',
          'Include my private expenses',
          initial: 'false',
          flag: true,
        ),
      ],
    );
    if (values == null) return;
    await run(() async {
      final results = await repo.search(
        start: values['start']!.isEmpty
            ? null
            : DateTime.parse(values['start']!),
        end: values['end']!.isEmpty ? null : DateTime.parse(values['end']!),
        text: values['text']!,
        category: values['category']!,
        payer: values['payer']!,
        minimum: values['min']!.isEmpty ? null : parseMoney(values['min']!),
        maximum: values['max']!.isEmpty ? null : parseMoney(values['max']!),
        includePersonal: values['personal'] == 'true',
      );
      if (mounted) setState(() => searchResults = results);
    });
  }

  Future<void> _switchGroup() async {
    await run(() async {
      final memberships = await widget.repository.profile
          .collection('memberships')
          .get();
      final homes = <Household>[];
      for (final membership in memberships.docs) {
        final doc = await widget.repository.db
            .collection('households')
            .doc(membership.id)
            .get();
        if (doc.exists) homes.add(Household(doc.id, doc.data()!));
      }
      if (!mounted) return;
      final choice = await showModalBottomSheet<Household>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final home in homes)
                ListTile(
                  title: Text(home.title),
                  onTap: () => Navigator.pop(context, home),
                ),
            ],
          ),
        ),
      );
      if (choice != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PlanningScreen(
              repository: widget.repository,
              household: choice,
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.enableItemIntelligence) {
      return Scaffold(
        appBar: AppBar(title: const Text('Planning & settlement')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'New planning tools await verified Firestore rules. Existing household expenses remain available.',
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.household.title),
          actions: [
            IconButton(
              tooltip: 'Export month',
              icon: const Icon(Icons.ios_share),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExportScreen(
                    repository: widget.repository,
                    home: widget.household,
                    month: month,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Change group filter',
              onPressed: busy ? null : _switchGroup,
              icon: const Icon(Icons.swap_horiz),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Reports & budget'),
              Tab(text: 'Repayments'),
              Tab(text: 'Recurring'),
              Tab(text: 'Search'),
              Tab(text: 'Personal'),
              Tab(text: 'Corrections'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => setState(
                    () => month = DateTime(month.year, month.month - 1),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(DateFormat.yMMMM().format(month)),
                IconButton(
                  onPressed: () => setState(
                    () => month = DateTime(month.year, month.month + 1),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Expanded(
              child: _query(
                _expenses,
                (source) => _query(
                  _payments,
                  (paymentRows) => _query(
                    _budgets,
                    (budgetRows) => _query(
                      _templates,
                      (templates) => _query(_personal, (privateRows) {
                        final expenses = source.docs
                            .map((d) => financeFromMap(d.id, d.data()))
                            .where((e) => monthKey(e.date) == monthKey(month))
                            .toList();
                        final previous = source.docs
                            .map((d) => financeFromMap(d.id, d.data()))
                            .where(
                              (e) =>
                                  monthKey(e.date) ==
                                  monthKey(
                                    DateTime(month.year, month.month - 1),
                                  ),
                            )
                            .toList();
                        final payments = paymentRows.docs
                            .map((d) => paymentFromMap(d.id, d.data()))
                            .where((p) => monthKey(p.date) == monthKey(month))
                            .toList();
                        final personal = privateRows.docs
                            .map(
                              (d) => financeFromMap(
                                d.id,
                                d.data(),
                                personal: true,
                              ),
                            )
                            .where((e) => monthKey(e.date) == monthKey(month))
                            .toList();
                        final budget = budgetRows.docs
                            .where((d) => d.id == monthKey(month))
                            .firstOrNull
                            ?.data();
                        final cached =
                            [
                              source,
                              paymentRows,
                              budgetRows,
                              templates,
                              privateRows,
                            ].any(
                              (s) =>
                                  s.metadata.isFromCache ||
                                  s.metadata.hasPendingWrites,
                            );
                        return Column(
                          children: [
                            if (cached)
                              const Text(
                                'Cached / pending data — not confirmed as current by server',
                              ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  ReportsTab(
                                    expenses: expenses,
                                    previous: previous,
                                    budget: budget,
                                    currency: widget.household.currency,
                                    editBudget: () => _budget(budget),
                                  ),
                                  PaymentsTab(
                                    payments: payments,
                                    settlement: financeSettlement(
                                      widget.household.members,
                                      widget.household.legacyMembers,
                                      expenses,
                                      payments,
                                    ),
                                    home: widget.household,
                                    add: () => _payment(payments, expenses),
                                    reverse: _reverse,
                                  ),
                                  RecurringTab(
                                    templates: templates.docs,
                                    month: month,
                                    currency: widget.household.currency,
                                    edit: _template,
                                    confirm: _confirmTemplate,
                                  ),
                                  SearchTab(
                                    results: searchResults,
                                    currency: widget.household.currency,
                                    search: _search,
                                  ),
                                  PersonalTab(
                                    entries: personal,
                                    currency: widget.household.currency,
                                  ),
                                  CorrectionsTab(
                                    documents: source.docs
                                        .where(
                                          (d) =>
                                              monthKey(
                                                (d.data()['date'] as Timestamp)
                                                    .toDate(),
                                              ) ==
                                              monthKey(month),
                                        )
                                        .toList(),
                                    amend: _amend,
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
          ],
        ),
      ),
    );
  }

  Widget _query(
    Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    Widget Function(QuerySnapshot<Map<String, dynamic>>) builder,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, s) {
      if (s.hasError) return RetryMessage(error: s.error!, retry: _reload);
      if (!s.hasData) return const Busy();
      return builder(s.data!);
    },
  );
}
