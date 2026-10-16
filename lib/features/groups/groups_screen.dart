import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data.dart';
import '../../widgets/common.dart';
import '../expenses/home_screen.dart';
import 'group_selection.dart';
import 'profile_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, this.repository});
  final HouseholdRepository? repository;
  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final repository = widget.repository ?? HouseholdRepository();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _memberships = repository
      .watchMemberships();
  GroupSelection? _selection;
  Object? _error;
  bool _loading = true, _restored = false;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
      _memberships = repository.watchMemberships();
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _selection = GroupSelection(prefs, repository.uid);
      // Recovery is idempotent. A timeout frees the shell without deleting Auth.
      await repository.ensureProfile().timeout(const Duration(seconds: 15));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String id) async {
    await _selection?.select(id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(repository: repository, householdId: id),
      ),
    );
  }

  Future<void> _createOrJoin(bool join) async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => GroupSetup(repository: repository, join: join),
      ),
    );
    if (id != null && mounted) await _open(id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My Groups / Homes'),
      actions: [
        IconButton(
          tooltip: 'Personal profile',
          icon: const Icon(Icons.person_outline),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProfileScreen(repository: repository),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            try {
              await FirebaseAuth.instance.signOut();
            } catch (error) {
              if (context.mounted) showError(context, error);
            }
          },
        ),
      ],
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _memberships,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (!_loading && _error == null && snapshot.hasData && !_restored) {
          _restored = true;
          final id = _selection?.resolve(docs.map((doc) => doc.id));
          if (id != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _open(id);
            });
          }
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Your personal account stays with you across homes. Choose a group to see its shared expenses.',
            ),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              RetryMessage(error: _error!, retry: _initialize),
            if (snapshot.hasError)
              RetryMessage(error: snapshot.error!, retry: _initialize),
            if (!_loading && _error == null) ...[
              FilledButton.icon(
                onPressed: () => _createOrJoin(false),
                icon: const Icon(Icons.add_home_outlined),
                label: const Text('Create group'),
              ),
              OutlinedButton.icon(
                onPressed: () => _createOrJoin(true),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Join with invite code'),
              ),
            ],
            const SizedBox(height: 20),
            if (snapshot.hasData && docs.isEmpty)
              const Text('No groups yet. Create a home or join your roommate.'),
            for (final membership in docs)
              _GroupTile(
                repository: repository,
                id: membership.id,
                open: () => _open(membership.id),
              ),
          ],
        );
      },
    ),
  );
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.repository,
    required this.id,
    required this.open,
  });
  final HouseholdRepository repository;
  final String id;
  final VoidCallback open;
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: repository.watchHousehold(id),
    builder: (context, snapshot) => Card(
      child: ListTile(
        leading: const Icon(Icons.home_outlined),
        title: Text(
          snapshot.data?.data()?['title'] as String? ?? 'Shared home',
        ),
        subtitle: Text(
          snapshot.hasError
              ? 'Unable to load. Tap to retry.'
              : '${(snapshot.data?.data()?['memberIds'] as List?)?.length ?? '…'} members',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: open,
      ),
    ),
  );
}

class GroupSetup extends StatefulWidget {
  const GroupSetup({super.key, required this.repository, required this.join});
  final HouseholdRepository repository;
  final bool join;
  @override
  State<GroupSetup> createState() => _GroupSetupState();
}

class _GroupSetupState extends State<GroupSetup> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  String _currency = 'EUR';
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.join
          ? await widget.repository.joinHousehold(_text.text)
          : await widget.repository.createHousehold(
              _text.text.trim(),
              _currency,
            );
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.join ? 'Join group' : 'Create group')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _text,
              enabled: !_busy,
              maxLength: widget.join ? 32 : 50,
              decoration: InputDecoration(
                labelText: widget.join ? 'Invite code' : 'Home / group name',
              ),
              validator: (value) => widget.join
                  ? (RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Paste the 32-character invitation code.')
                  : ((value?.trim().isEmpty ?? true)
                        ? 'Enter a group name.'
                        : null),
            ),
            if (!widget.join) ...[
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: ['EUR', 'BDT', 'USD', 'GBP', 'INR']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _currency = v!),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'A home starts with room for two people. Expenses use the existing equal split. Currency stays fixed.',
                ),
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy
                    ? 'Saving…'
                    : widget.join
                    ? 'Join group'
                    : 'Create group',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
