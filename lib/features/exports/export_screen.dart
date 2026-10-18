import 'package:basha_hisab/l10n/app_text.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data.dart';
import '../../domain.dart';
import '../../widgets/common.dart';
import '../planning/planning_domain.dart';
import '../planning/planning_repository.dart';
import 'report.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.repository,
    required this.home,
    required this.month,
  });
  final HouseholdRepository repository;
  final Household home;
  final DateTime month;
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool personal = false, busy = false;
  Future<void> export(bool pdf) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final repo = widget.repository;
      final uid = repo.uid;
      final group = repo.db.collection('households').doc(widget.home.id);
      final month =
          '${widget.month.year}-${widget.month.month.toString().padLeft(2, '0')}';
      final source = await group
          .collection('expenses')
          .where('month', isEqualTo: month)
          .get();
      final payments = await group
          .collection('payments')
          .where('month', isEqualTo: month)
          .get();
      final private = personal
          ? await repo.profile
                .collection('personalExpenses')
                .where('month', isEqualTo: month)
                .get()
          : null;
      final entries = <FinanceEntry>[];
      final items = <String, List<ExpenseItem>>{};
      var cached =
          source.metadata.isFromCache ||
          payments.metadata.isFromCache ||
          (private?.metadata.isFromCache ?? false);
      for (final doc in [
        ...source.docs,
        ...?private?.docs.where((d) => d.data()['groupId'] == widget.home.id),
      ]) {
        final isPrivate = doc.reference.path.startsWith('users/');
        entries.add(financeFromMap(doc.id, doc.data(), personal: isPrivate));
        final rows = await doc.reference
            .collection('items')
            .orderBy('index')
            .get();
        cached = cached || rows.metadata.isFromCache;
        items['${isPrivate ? 'private' : 'shared'}/${doc.id}'] = rows.docs
            .map(
              (d) => ExpenseItem(
                d.data()['name'] as String,
                d.data()['amount'] as int,
                quantityMilli: d.data()['quantityMilli'] as int?,
                unit: d.data()['unit'] as String?,
              ),
            )
            .toList();
      }
      final report = MonthlyReport(
        widget.home,
        widget.month,
        entries,
        items,
        payments.docs.map((d) => paymentFromMap(d.id, d.data())).toList(),
        asOf: DateTime.now(),
        cached: cached,
      );
      final bytes = pdf
          ? await report.pdf(
              await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
            )
          : report.excel();
      if (repo.auth.currentUser?.uid != uid) {
        throw StateError('Account changed. Export cancelled.');
      }
      final directory = await Directory(
        '${(await getTemporaryDirectory()).path}/exports',
      ).create(recursive: true);
      final file = File(
        '${directory.path}/BashaHisab-$month-${DateTime.now().microsecondsSinceEpoch}.${pdf ? 'pdf' : 'xlsx'}',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Export this month')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${widget.home.title} · ${widget.month.toIso8601String().substring(0, 7)}',
        ),
        const Text(
          'Includes expenses, item rows, transfers, references and settlement. Cached data is marked. Images stay on this phone.',
        ),
        SwitchListTile(
          title: const AppText('Include my private expenses'),
          subtitle: const Text(
            'Private rows become visible to anyone you share this file with.',
          ),
          value: personal,
          onChanged: busy ? null : (v) => setState(() => personal = v),
        ),
        if (busy) const LinearProgressIndicator(),
        FilledButton(
          onPressed: busy ? null : () => export(true),
          child: const AppText('Share PDF'),
        ),
        OutlinedButton(
          onPressed: busy ? null : () => export(false),
          child: const AppText('Share Excel (.xlsx)'),
        ),
      ],
    ),
  );
}
