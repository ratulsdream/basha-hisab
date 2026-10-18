import 'package:basha_hisab/l10n/app_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../data.dart';
import '../../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.repository});
  final HouseholdRepository repository;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  bool _loaded = false, _busy = false;
  late final _profile = widget.repository.watchProfile();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repository.updateProfile(_name.text);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: AppText('Profile saved')));
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Personal profile')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return RetryMessage(
            error: snapshot.error!,
            retry: () => setState(() {}),
          );
        }
        final data = snapshot.data?.data();
        if (data == null) {
          return const Busy(message: 'Loading your personal profile…');
        }
        if (!_loaded) {
          _loaded = true;
          _name.text = data['displayName'] as String? ?? '';
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(data['email'] as String? ?? ''),
            const SizedBox(height: 12),
            SelectableText('Account ID: ${widget.repository.uid}'),
            if (data['createdAt'] is Timestamp)
              Text(
                'Account created: ${(data['createdAt'] as Timestamp).toDate().toLocal().toIso8601String().split('T').first}',
              ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              maxLength: 50,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: tr(context, 'Display name'),
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save profile'),
            ),
            ListTile(
              title: const AppText('Open source licenses'),
              leading: const Icon(Icons.info_outline),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'BashaHisab',
                applicationVersion: '3.0.0-phase.3',
              ),
            ),
            const Text(
              'Your account remains active when you leave a home. Existing expense payer names are preserved in each home’s history.',
            ),
          ],
        );
      },
    ),
  );
}
