import 'package:flutter/material.dart';
import '../../l10n/app_text.dart';
import '../sync/outbox_store.dart';

class DraftStatus extends StatefulWidget {
  const DraftStatus({super.key, required this.uid, required this.open});
  final String uid;
  final VoidCallback open;
  @override
  State<DraftStatus> createState() => _DraftStatusState();
}

class _DraftStatusState extends State<DraftStatus> {
  late final stream = OutboxStore.open(
    widget.uid,
  ).then((store) => store.watch());
  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<Stream<List<QueuedExpense>>>(
    future: stream,
    builder: (context, f) {
      if (f.hasError) {
        return TextButton.icon(
          onPressed: widget.open,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const AppText('Pending drafts'),
        );
      }
      if (!f.hasData) return const SizedBox.shrink();
      return StreamBuilder<List<QueuedExpense>>(
        stream: f.data,
        builder: (context, s) {
          if (s.data?.isEmpty ?? true) return const SizedBox.shrink();
          return Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(
                '${s.data!.length} · ${tr(context, 'Pending drafts')}',
              ),
              subtitle: const AppText(
                'Offline drafts are saved on this phone. Open Pending drafts to review upload status.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.open,
            ),
          );
        },
      );
    },
  );
}
