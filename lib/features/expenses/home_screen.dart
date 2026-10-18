import '../../l10n/app_text.dart';
import '../shell/dashboard_tab.dart';
import '../shell/preferences_screen.dart';
import '../groups/profile_screen.dart';
import '../sync/outbox_screen.dart';
import '../notifications/notification_screen.dart';
import '../exports/export_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../planning/planning_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.householdId,
    this.refreshNotifications,
  });
  final HouseholdRepository repository;
  final String householdId;
  final Future<void> Function()? refreshNotifications;
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
  int _tab = 0, _itemTab = 0;
  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _expenses = widget.repository.watchExpenses(widget.householdId, _month);
    });
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

  Future<void> _leave(Household household) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('Leave this group?'),
        content: const Text(
          'You will lose access to this home. All expenses remain for its members, and your personal account stays active. Save any unsettled balance first. A valid invite is needed to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('Leave group'),
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
        title: const AppText('Invite your roommate'),
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
            child: const AppText('Close'),
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
            child: const AppText('Share code'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: household.inviteCode),
              );
              if (context.mounted && mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: AppText('Invitation code copied')),
                );
              }
            },
            child: const AppText('Copy code'),
          ),
        ],
      ),
    );
  }

  void _items([int tab = 0]) => setState(() {
    _itemTab = tab;
    _tab = 1;
  });
  void _planning(Household home, [int tab = 0, DateTime? month]) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlanningScreen(
            repository: widget.repository,
            household: home,
            initialTab: tab,
            initialMonth: month,
          ),
        ),
      );
  void _profile() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(repository: widget.repository),
    ),
  );
  void _pending() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OutboxScreen(repository: widget.repository),
    ),
  );
  Future<void> _scan(Household home) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: AppText(
                'Choose receipt source',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const AppText('Scan with camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const AppText('Choose receipt from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null && mounted) await _add(home, source: source);
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _house,
        builder: (context, s) {
          final home = s.hasData && s.data!.exists
              ? Household(s.data!.id, s.data!.data()!)
              : null;
          return PopScope(
            canPop: !_scanning,
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: Tooltip(
                  message: tr(context, 'Switch group'),
                  child: TextButton.icon(
                    onPressed: _scanning ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.home_outlined),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            home?.title ?? 'BashaHisab',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.expand_more),
                      ],
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: tr(context, 'Personal profile'),
                    onPressed: _scanning ? null : _profile,
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: _scanning
                    ? null
                    : (v) => setState(() => _tab = v),
                destinations: [
                  for (final entry in [
                    (Icons.home_outlined, 'Home'),
                    (Icons.inventory_2_outlined, 'Items'),
                    (Icons.history, 'History'),
                    (Icons.grid_view_outlined, 'More'),
                  ])
                    NavigationDestination(
                      icon: Icon(entry.$1),
                      label: tr(context, entry.$2),
                    ),
                ],
              ),
              body: SafeArea(
                top: false,
                child: _scanning
                    ? const Busy(message: 'Reading receipt on your device…')
                    : s.hasError
                    ? RetryMessage(
                        error: s.error!,
                        retry: () => setState(
                          () => _house = widget.repository.watchHousehold(
                            widget.householdId,
                          ),
                        ),
                      )
                    : home == null
                    ? const Busy(message: 'Loading your home…')
                    : switch (_tab) {
                        0 => DashboardTab(
                          key: ValueKey(home.id),
                          repository: widget.repository,
                          home: home,
                          scan: () => _scan(home),
                          add: () => _add(home),
                          shopping: () => _items(2),
                          history: () => setState(() => _tab = 2),
                          regular: () => _items(1),
                          budget: () => _planning(home),
                          invite: () => _invite(home),
                          pending: _pending,
                        ),
                        1 => ItemsScreen(
                          key: ValueKey('${home.id}:$_itemTab'),
                          repository: ItemsRepository(
                            widget.repository.db,
                            widget.repository.uid,
                            home.id,
                          ),
                          household: home,
                          enabled: widget.repository.enableItemIntelligence,
                          initialTab: _itemTab,
                          embedded: true,
                          onHistory: () => setState(() => _tab = 2),
                        ),
                        2 => _history(home),
                        _ => _more(home),
                      },
              ),
            ),
          );
        },
      );
  Widget _history(Household home) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: tr(context, 'Previous month'),
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(_month),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: tr(context, 'Next month'),
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in [
              ('Search and filters', 3),
              ('Category breakdown', 0),
              ('Payment history', 1),
              ('Personal & shared expenses', 4),
              ('Export PDF / Excel', -1),
            ])
              ActionChip(
                label: AppText(entry.$1),
                avatar: Icon(
                  entry.$2 == -1 ? Icons.ios_share : Icons.tune,
                  size: 18,
                ),
                onPressed: () =>
                    entry.$2 == -1 && widget.repository.enableItemIntelligence
                    ? Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExportScreen(
                            repository: widget.repository,
                            home: home,
                            month: _month,
                          ),
                        ),
                      )
                    : _planning(home, entry.$2 < 0 ? 0 : entry.$2, _month),
              ),
          ],
        ),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _expenses,
          builder: (context, s) {
            if (s.hasError) {
              return RetryMessage(
                error: s.error!,
                retry: () => setState(
                  () => _expenses = widget.repository.watchExpenses(
                    home.id,
                    _month,
                  ),
                ),
              );
            }
            if (!s.hasData) return const Busy(message: 'Loading expenses…');
            final rows =
                s.data!.docs
                    .map((d) => Expense(d.id, d.data()))
                    .where((e) => !e.voided)
                    .toList()
                  ..sort((a, b) => b.date.compareTo(a.date));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (s.data!.metadata.isFromCache ||
                    s.data!.metadata.hasPendingWrites)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: AppText(
                        'Local data — totals may be incomplete until connected.',
                      ),
                    ),
                  ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: AppText('No expenses this month.'),
                  ),
                for (final e in rows)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(e.merchant),
                      subtitle: Text(
                        '${DateFormat.yMMMd().format(e.date)} · ${home.name(e.payer)}${e.refund ? ' · ${tr(context, 'Refund')}' : ''}',
                      ),
                      trailing: Text(
                        displayMoney(
                          home.currency,
                          e.refund ? -e.total : e.total,
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExpenseDetails(
                            expense: e,
                            household: home,
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
  );
  Widget _more(Household home) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      for (final entry in <({IconData icon, String title, VoidCallback tap})>[
        (icon: Icons.person_outline, title: 'Personal profile', tap: _profile),
        (
          icon: Icons.swap_horiz,
          title: 'Manage groups',
          tap: () => Navigator.pop(context),
        ),
        (
          icon: Icons.person_add_outlined,
          title: 'Invitations',
          tap: () => _invite(home),
        ),
        (
          icon: Icons.account_balance_wallet_outlined,
          title: 'Budget settings',
          tap: () => _planning(home),
        ),
        (
          icon: Icons.repeat,
          title: 'Recurring bills',
          tap: () => _planning(home, 2),
        ),
        (
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          tap: () async {
            if (!widget.repository.enableItemIntelligence) {
              _planning(home);
              return;
            }
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    NotificationScreen(repository: widget.repository),
              ),
            );
            try {
              await widget.refreshNotifications?.call();
            } catch (e) {
              if (mounted) showError(context, e);
            }
          },
        ),
        (
          icon: Icons.translate,
          title: 'Language & appearance',
          tap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PreferencesScreen()),
          ),
        ),
        (
          icon: Icons.settings_outlined,
          title: 'App settings',
          tap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PreferencesScreen()),
          ),
        ),
        if (widget.repository.enableItemIntelligence)
          (
            icon: Icons.cloud_upload_outlined,
            title: 'Pending drafts',
            tap: _pending,
          ),
        (
          icon: Icons.exit_to_app,
          title: 'Leave group',
          tap: () => _leave(home),
        ),
        (
          icon: Icons.logout,
          title: 'Sign out',
          tap: () async {
            try {
              await widget.repository.auth.signOut();
              if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            } catch (e) {
              if (mounted) showError(context, e);
            }
          },
        ),
      ])
        Card(
          child: ListTile(
            leading: Icon(entry.icon),
            title: AppText(entry.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: entry.tap,
          ),
        ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: AppText(
          'Receipt photos stay on your phone. Only reviewed expense data is shared with your home.',
        ),
      ),
    ],
  );
}
