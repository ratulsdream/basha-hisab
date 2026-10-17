import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../data.dart';
import '../../domain.dart';

import '../../widgets/common.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../groups/group_selection.dart';
import 'expense_editor.dart';
import 'expense_details.dart';
import '../receipts/receipt_ocr.dart';
import '../items/items_screen.dart';
import '../items/items_repository.dart';
import '../planning/planning_domain.dart';
import '../planning/planning_repository.dart';
import '../planning/planning_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.householdId,
  });
  final HouseholdRepository repository;
  final String householdId;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _house = widget.repository
      .watchHousehold(widget.householdId);
  late Stream<QuerySnapshot<Map<String, dynamic>>> _expenses = widget.repository
      .watchExpenses(widget.householdId, _month);
  bool _scanning = false;
  List<Repayment> _payments = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _paymentSubscription;
  Object? _paymentError;
  bool _paymentReady = false, _paymentCached = false;
  @override
  void initState() {
    super.initState();
    _listenPayments();
  }

  void _listenPayments() {
    _paymentSubscription?.cancel();
    if (!widget.repository.enableItemIntelligence) return;
    _paymentReady = false;
    _paymentError = null;
    _payments = [];
    _paymentSubscription =
        PlanningRepository(
              widget.repository.db,
              widget.repository.uid,
              widget.householdId,
            )
            .collection('payments')
            .where('month', isEqualTo: monthKey(_month))
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                if (mounted) {
                  setState(() {
                    _payments = snapshot.docs
                        .map((d) => paymentFromMap(d.id, d.data()))
                        .toList();
                    _paymentReady = true;
                    _paymentCached =
                        snapshot.metadata.isFromCache ||
                        snapshot.metadata.hasPendingWrites;
                  });
                }
              },
              onError: (Object e) {
                if (mounted) setState(() => _paymentError = e);
              },
            );
  }

  @override
  void dispose() {
    _paymentSubscription?.cancel();
    super.dispose();
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _expenses = widget.repository.watchExpenses(widget.householdId, _month);
    });
    _listenPayments();
  }

  Future<void> _add(Household household, {ImageSource? source}) async {
    ReceiptDraft draft = const ReceiptDraft();
    if (source != null) {
      setState(() => _scanning = true);

      try {
        final image = await ImagePicker().pickImage(
          source: source,
          maxWidth: 2400,
          imageQuality: 90,
        );
        if (image == null) return;
        draft = await ReceiptOcr().scan(image.path);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(receiptScanError(error))));
        }
        return;
      } finally {
        if (mounted) setState(() => _scanning = false);
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpenseEditor(
          repository: widget.repository,
          household: household,
          draft: draft,
          fromReceipt: source != null,
        ),
      ),
    );
  }

  Future<void> _chooseAdd(Household household) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Enter manually'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Scan with camera'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose receipt from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) {
      await _add(
        household,
        source: choice == 'manual'
            ? null
            : choice == 'camera'
            ? ImageSource.camera
            : ImageSource.gallery,
      );
    }
  }

  Future<void> _leave(Household household) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this group?'),
        content: const Text(
          'You will lose access to this home. All expenses remain for its members, and your personal account stays active. Save any unsettled balance first. A valid invite is needed to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave group'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.leaveGroup(household.id);
      final prefs = await SharedPreferences.getInstance();
      await GroupSelection(prefs, widget.repository.uid).clear();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  void _invite(Household household) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite your roommate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this private code with your roommate. They must create an account and choose Join. It can be used by only one other person.',
            ),
            const SizedBox(height: 16),
            SelectableText(household.inviteCode),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              final box = context.findRenderObject() as RenderBox?;
              SharePlus.instance.share(
                ShareParams(
                  text:
                      'Join my BashaHisab home with this invite code: ${household.inviteCode}',
                  sharePositionOrigin: box == null
                      ? null
                      : box.localToGlobal(Offset.zero) & box.size,
                ),
              );
            },
            child: const Text('Share code'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: household.inviteCode),
              );
              if (context.mounted && mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Invitation code copied')),
                );
              }
            },
            child: const Text('Copy code'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _house,
    builder: (context, houseSnapshot) {
      final household = houseSnapshot.hasData && houseSnapshot.data!.exists
          ? Household(houseSnapshot.data!.id, houseSnapshot.data!.data()!)
          : null;
      return Scaffold(
        appBar: AppBar(
          title: Text(household?.title ?? 'BashaHisab'),
          leading: IconButton(
            tooltip: 'Switch group',
            icon: const Icon(Icons.swap_horiz),
            onPressed: _scanning ? null : () => Navigator.pop(context),
          ),
          actions: [
            if (household != null)
              IconButton(
                tooltip: 'Planning & settlement',
                icon: const Icon(Icons.account_balance_wallet_outlined),
                onPressed: _scanning
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlanningScreen(
                            repository: widget.repository,
                            household: household,
                          ),
                        ),
                      ),
              ),
            if (household != null)
              IconButton(
                tooltip: 'Grocery & kitchen',
                icon: const Icon(Icons.kitchen_outlined),
                onPressed: _scanning
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ItemsScreen(
                            repository: ItemsRepository(
                              widget.repository.db,
                              widget.repository.uid,
                              household.id,
                            ),
                            household: household,
                            enabled: widget.repository.enableItemIntelligence,
                          ),
                        ),
                      ),
              ),
            if (household?.members.length == 1)
              IconButton(
                tooltip: 'Invite roommate',
                onPressed: () => _invite(household!),
                icon: const Icon(Icons.person_add_outlined),
              ),
            if (household != null)
              IconButton(
                tooltip: 'Leave group',
                icon: const Icon(Icons.exit_to_app),
                onPressed: _scanning ? null : () => _leave(household),
              ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: _scanning
                  ? null
                  : () async {
                      try {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst);
                        }
                      } catch (error) {
                        if (context.mounted) showError(context, error);
                      }
                    },
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        floatingActionButton: household == null || _scanning
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _chooseAdd(household),
                icon: const Icon(Icons.add),
                label: const Text('Add expense'),
              ),
        body: _scanning
            ? const Busy(message: 'Reading receipt on your device…')
            : houseSnapshot.hasError
            ? RetryMessage(
                error: houseSnapshot.error!,
                retry: () => setState(
                  () => _house = widget.repository.watchHousehold(
                    widget.householdId,
                  ),
                ),
              )
            : household == null
            ? const Busy()
            : Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        DateFormat.yMMMM().format(_month),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _expenses,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return RetryMessage(
                            error: snapshot.error!,
                            retry: () => setState(
                              () => _expenses = widget.repository.watchExpenses(
                                widget.householdId,
                                _month,
                              ),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Busy(message: 'Loading expenses…');
                        }
                        final expenses =
                            snapshot.data!.docs
                                .map((doc) => Expense(doc.id, doc.data()))
                                .where((expense) => !expense.voided)
                                .toList()
                              ..sort((a, b) => b.date.compareTo(a.date));
                        if (widget.repository.enableItemIntelligence &&
                            _paymentError != null) {
                          return RetryMessage(
                            error: _paymentError!,
                            retry: () => setState(_listenPayments),
                          );
                        }
                        if (widget.repository.enableItemIntelligence &&
                            !_paymentReady) {
                          return const Busy(message: 'Loading settlement…');
                        }
                        final settlement =
                            widget.repository.enableItemIntelligence
                            ? financeSettlement(
                                household.members,
                                household.legacyMembers,
                                expenses.map(
                                  (e) => FinanceEntry(
                                    id: e.id,
                                    merchant: e.merchant,
                                    payer: e.payer,
                                    date: e.date,
                                    amount: e.total,
                                    category: e.category,
                                    refund: e.refund,
                                    voided: e.voided,
                                    splits: e.splits,
                                    members: e.splitBetween,
                                  ),
                                ),
                                _payments,
                              )
                            : calculateGroupSettlement(
                                household.members,
                                household.legacyMembers,
                                expenses.map(
                                  (e) => (
                                    payer: e.payer,
                                    amount: e.total,
                                    splitBetween: e.splitBetween,
                                  ),
                                ),
                              );
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          children: [
                            if (snapshot.data!.metadata.isFromCache ||
                                snapshot.data!.metadata.hasPendingWrites ||
                                _paymentCached)
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Showing local data. Changes sync when connected; totals may be incomplete while offline.',
                                  ),
                                ),
                              ),
                            if (household.members.length == 1)
                              Card(
                                child: ListTile(
                                  title: const Text(
                                    'Your roommate has not joined yet',
                                  ),
                                  subtitle: const Text(
                                    'Invite them to see who owes whom.',
                                  ),
                                  trailing: const Icon(
                                    Icons.person_add_outlined,
                                  ),
                                  onTap: () => _invite(household),
                                ),
                              ),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Total household spending'),
                                    const SizedBox(height: 8),
                                    Text(
                                      displayMoney(
                                        household.currency,
                                        settlement.total,
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineMedium,
                                    ),
                                    const Divider(height: 28),
                                    for (final id in settlement.paid.keys)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${household.name(id)}${id == widget.repository.uid ? ' (you)' : ''}',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                            Text(
                                              'Paid ${displayMoney(household.currency, settlement.paid[id]!)}',
                                            ),
                                            Text(
                                              'Equal share ${displayMoney(household.currency, settlement.shares[id]!)}',
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (settlement.total.isOdd)
                                      const Text(
                                        'An odd cent goes to the first roommate by account ID, so shares always add up exactly.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    if (household.members.length == 2 ||
                                        settlement.transfers.isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        margin: const EdgeInsets.only(top: 8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          settlement.transfers.isEmpty
                                              ? 'All square — no one owes anything.'
                                              : settlement.transfers
                                                    .map(
                                                      (transfer) =>
                                                          '${household.name(transfer.debtor)} owes ${household.name(transfer.creditor)} ${displayMoney(household.currency, transfer.amount)}',
                                                    )
                                                    .join('\n'),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Expense history',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            if (expenses.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 28),
                                child: Text(
                                  'No expenses this month. Add your first shared expense.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            for (final expense in expenses)
                              Card(
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.receipt_long_outlined),
                                  ),
                                  title: Text(
                                    '${expense.refund ? 'Refund · ' : ''}${expense.merchant}',
                                  ),
                                  subtitle: Text(
                                    '${DateFormat.yMMMd().format(expense.date)} · Paid by ${household.name(expense.payer)}',
                                  ),
                                  trailing: Text(
                                    displayMoney(
                                      household.currency,
                                      expense.refund
                                          ? -expense.total
                                          : expense.total,
                                    ),
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ExpenseDetails(
                                        expense: expense,
                                        household: household,
                                        repository: widget.repository,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
      );
    },
  );
}
