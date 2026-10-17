import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data.dart';
import '../../widgets/common.dart';
import 'outbox_store.dart';
import 'outbox_service.dart';

class OutboxScreen extends StatefulWidget {
  const OutboxScreen({super.key, required this.repository});
  final HouseholdRepository repository;
  @override
  State<OutboxScreen> createState() => _OutboxScreenState();
}

class _OutboxScreenState extends State<OutboxScreen> {
  late final future = OutboxStore.open(widget.repository.uid);
  bool busy = false;
  Future<void> _retry(
    OutboxStore store,
    QueuedExpense draft, {
    bool approve = false,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (approve) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm a separate purchase'),
            content: Text(
              '${draft.payload['merchant']} · ${draft.payload['date']}\n${draft.payload['total']} cents\nReview the shared history first. This override applies only to duplicate detection and does not bypass membership checks.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('I reviewed — separate purchase'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await store.approveDuplicate(draft.id);
      } else {
        await store.mark(draft.id, 'pending', 'Retry requested');
      }
      await OutboxService(store, widget.repository).drain();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _export(QueuedExpense draft) async {
    try {
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/BashaHisab-draft-${draft.id}.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(draft.payload),
      );
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
    }
  }

  Future<void> _discard(OutboxStore store, QueuedExpense draft) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this local draft?'),
        content: const Text(
          'This never deletes a server expense. If a connection failed after upload, check history before entering it again. Export the draft first if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove local draft'),
          ),
        ],
      ),
    );
    if (ok == true) await store.remove(draft.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pending expenses on this phone')),
    body: FutureBuilder<OutboxStore>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return RetryMessage(
            error: snapshot.error!,
            retry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) return const Busy();
        final store = snapshot.data!;
        return StreamBuilder<List<QueuedExpense>>(
          stream: store.watch(),
          builder: (context, s) {
            if (s.hasError) {
              return RetryMessage(
                error: s.error!,
                retry: () => setState(() {}),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Local drafts are not server-confirmed expenses. They stay with this account across restarts and never move automatically between groups.',
                ),
                if (busy) const LinearProgressIndicator(),
                if (s.hasData && s.data!.isEmpty)
                  const ListTile(title: Text('No pending drafts.')),
                for (final draft in s.data ?? <QueuedExpense>[])
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${draft.payload['merchant']} · ${draft.payload['date']}',
                          ),
                          Text(
                            '${draft.payload['total']} cents · ${draft.payload['personal'] == true ? 'Private' : 'Shared'} · ${draft.state}',
                          ),
                          Text(draft.reason),
                          ExpansionTile(
                            title: const Text('Review extracted items'),
                            children: [
                              for (final item in draft.payload['items'] as List)
                                ListTile(
                                  title: Text('${item['name']}'),
                                  trailing: Text('${item['amount']} cents'),
                                ),
                            ],
                          ),
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _retry(store, draft),
                                child: const Text('Retry'),
                              ),
                              if (draft.reason.startsWith('Possible duplicate'))
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () =>
                                            _retry(store, draft, approve: true),
                                  child: const Text(
                                    'Review duplicate override',
                                  ),
                                ),
                              TextButton(
                                onPressed: () => _export(draft),
                                child: const Text('Export local draft'),
                              ),
                              TextButton(
                                onPressed: () => _discard(store, draft),
                                child: const Text('Remove local draft'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
