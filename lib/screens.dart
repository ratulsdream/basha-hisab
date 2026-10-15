import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'data.dart';
import 'domain.dart';

String displayMoney(String currency, int cents) =>
    '$currency ${NumberFormat('#,##0.00').format(cents / 100)}';
void showError(BuildContext context, Object error) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(friendlyError(error))));

class Busy extends StatelessWidget {
  const Busy({super.key, this.message = 'Loading…'});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    ),
  );
}

class RetryMessage extends StatelessWidget {
  const RetryMessage({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(friendlyError(error), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: RetryMessage(
            error: snapshot.error!,
            retry: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const AuthGate()),
            ),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Busy());
      }
      return snapshot.data == null
          ? const AuthScreen()
          : HouseholdGate(key: ValueKey(snapshot.data!.uid));
    },
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false, _busy = false, _obscure = true;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (_register) {
        await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter your email above to reset your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _email.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'If an account exists, a password reset email has been sent.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.home_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'BashaHisab',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const Text(
                      'One home. Two roommates. Clear expenses.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      _register ? 'Create your account' : 'Welcome back',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) =>
                          value != null &&
                              RegExp(r'^\S+@\S+\.\S+$').hasMatch(value.trim())
                          ? null
                          : 'Enter a valid email.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _obscure,
                      autofillHints: [
                        _register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (value) => (value?.length ?? 0) >= 6
                          ? null
                          : 'Use at least 6 characters.',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? 'Please wait…'
                            : _register
                            ? 'Create account'
                            : 'Sign in',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _register = !_register;
                              _error = null;
                            }),
                      child: Text(
                        _register
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                    if (!_register)
                      TextButton(
                        onPressed: _busy ? null : _reset,
                        child: const Text('Forgot password?'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class HouseholdGate extends StatefulWidget {
  const HouseholdGate({super.key});
  @override
  State<HouseholdGate> createState() => _HouseholdGateState();
}

class _HouseholdGateState extends State<HouseholdGate> {
  final repository = HouseholdRepository();
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _profile = repository
      .watchProfile();
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profile,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('BashaHisab')),
              body: RetryMessage(
                error: snapshot.error!,
                retry: () =>
                    setState(() => _profile = repository.watchProfile()),
              ),
            );
          }
          if (!snapshot.hasData) return const Scaffold(body: Busy());
          if (!snapshot.data!.exists) {
            return HouseholdSetup(repository: repository);
          }
          return HomeScreen(
            repository: repository,
            householdId: snapshot.data!.data()!['householdId'] as String,
          );
        },
      );
}

class HouseholdSetup extends StatefulWidget {
  const HouseholdSetup({super.key, required this.repository});
  final HouseholdRepository repository;
  @override
  State<HouseholdSetup> createState() => _HouseholdSetupState();
}

class _HouseholdSetupState extends State<HouseholdSetup> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _join = false, _busy = false;
  String _currency = 'BDT';
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_join) {
        await widget.repository.joinHousehold(_name.text.trim(), _code.text);
      } else {
        await widget.repository.createHousehold(_name.text.trim(), _currency);
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Your shared home'),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: _busy
              ? null
              : () async {
                  try {
                    await FirebaseAuth.instance.signOut();
                  } catch (error) {
                    if (context.mounted) showError(context, error);
                  }
                },
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A household for two',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create a home and invite your roommate, or join using their code. Each account belongs to one household.',
                ),
                const SizedBox(height: 24),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Create')),
                    ButtonSegment(value: true, label: Text('Join')),
                  ],
                  selected: {_join},
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _join = value.single;
                          _error = null;
                        }),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 50,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Enter your name.'
                      : null,
                ),
                const SizedBox(height: 12),
                if (_join)
                  TextFormField(
                    controller: _code,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Invitation code',
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^[a-fA-F0-9]{32}$',
                        ).hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Paste the 32-character code from your roommate.',
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Household currency',
                    ),
                    items: ['BDT', 'USD', 'EUR', 'GBP', 'INR']
                        .map(
                          (code) =>
                              DropdownMenuItem(value: code, child: Text(code)),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _currency = value!),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Expenses are split equally. Your household currency stays fixed; no currency conversion is performed.',
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    _busy
                        ? 'Saving…'
                        : _join
                        ? 'Join household'
                        : 'Create household',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

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
  void _changeMonth(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _expenses = widget.repository.watchExpenses(widget.householdId, _month);
  });
  Future<void> _add(Household household, {ImageSource? source}) async {
    ReceiptDraft draft = const ReceiptDraft();
    if (source != null) {
      setState(() => _scanning = true);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final image = await ImagePicker().pickImage(
          source: source,
          maxWidth: 2400,
          imageQuality: 90,
        );
        if (image == null) return;
        final recognized = await recognizer.processImage(
          InputImage.fromFilePath(image.path),
        );
        draft = parseReceipt(recognized.text);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Receipt could not be read. Check camera/photo permissions or enter the expense manually.',
              ),
            ),
          );
        }
        return;
      } finally {
        await recognizer.close();
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
          title: const Text('BashaHisab'),
          actions: [
            if (household?.members.length == 1)
              IconButton(
                tooltip: 'Invite roommate',
                onPressed: () => _invite(household!),
                icon: const Icon(Icons.person_add_outlined),
              ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: _scanning
                  ? null
                  : () async {
                      try {
                        await FirebaseAuth.instance.signOut();
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
                                .toList()
                              ..sort((a, b) => b.date.compareTo(a.date));
                        final settlement = calculateSettlement(
                          household.members,
                          expenses.map(
                            (e) => (payer: e.payer, amount: e.total),
                          ),
                        );
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          children: [
                            if (snapshot.data!.metadata.isFromCache ||
                                snapshot.data!.metadata.hasPendingWrites)
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
                                    for (final id in household.members)
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
                                              '50% share ${displayMoney(household.currency, settlement.shares[id]!)}',
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (settlement.total.isOdd)
                                      const Text(
                                        'An odd cent goes to the first roommate by account ID, so shares always add up exactly.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    if (household.members.length == 2)
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
                                          settlement.amount == 0
                                              ? 'All square — no one owes anything.'
                                              : '${household.name(settlement.debtor!)} owes ${household.name(settlement.creditor!)} ${displayMoney(household.currency, settlement.amount)}',
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
                                  title: Text(expense.merchant),
                                  subtitle: Text(
                                    '${DateFormat.yMMMd().format(expense.date)} · Paid by ${household.name(expense.payer)}',
                                  ),
                                  trailing: Text(
                                    displayMoney(
                                      household.currency,
                                      expense.total,
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

class _ItemFields {
  _ItemFields([ExpenseItem? item])
    : name = TextEditingController(text: item?.name ?? ''),
      amount = TextEditingController(
        text: item == null ? '' : moneyInput(item.amount),
      );
  final TextEditingController name, amount;
  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class ExpenseEditor extends StatefulWidget {
  const ExpenseEditor({
    super.key,
    required this.repository,
    required this.household,
    required this.draft,
    required this.fromReceipt,
  });
  final HouseholdRepository repository;
  final Household household;
  final ReceiptDraft draft;
  final bool fromReceipt;
  @override
  State<ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<ExpenseEditor> {
  final _form = GlobalKey<FormState>();
  late final _merchant = TextEditingController(text: widget.draft.merchant);
  late final _total = TextEditingController(
    text: widget.draft.total == null ? '' : moneyInput(widget.draft.total!),
  );
  late final List<_ItemFields> _items = widget.draft.items
      .map(_ItemFields.new)
      .toList();
  late DateTime _date = widget.draft.date ?? DateTime.now();
  late String _payer = widget.repository.uid;
  late final String _id = widget.repository.newExpenseId(widget.household.id);
  bool _saving = false, _reviewed = false;
  String? _error;
  @override
  void dispose() {
    _merchant.dispose();
    _total.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    // Validate controllers as well as mounted fields: long receipts are lazy
    // lists, and fields outside the viewport may not currently be in the Form.
    final parsedTotal = parseMoney(_total.text);
    String? validationError;
    if (_merchant.text.trim().isEmpty || _merchant.text.trim().length > 100) {
      validationError =
          'Enter a merchant or expense name (up to 100 characters).';
    } else if (parsedTotal == null || parsedTotal <= 0) {
      validationError = 'Enter a total greater than zero (up to 10,000,000).';
    } else {
      for (var index = 0; index < _items.length; index++) {
        final item = _items[index];
        if (item.name.text.trim().isEmpty ||
            item.name.text.trim().length > 100 ||
            parseMoney(item.amount.text) == null) {
          validationError =
              'Check item ${index + 1}: enter a name up to 100 characters and a valid price.';
          break;
        }
      }
    }
    final visibleFieldsValid = _form.currentState!.validate();
    if (validationError != null || !visibleFieldsValid) {
      setState(() => _error = validationError);
      return;
    }

    if (widget.fromReceipt && !_reviewed) {
      setState(
        () => _error =
            'Review the receipt fields and confirm the checkbox before saving.',
      );
      return;
    }
    final total = parseMoney(_total.text)!;
    final itemTotal = _items.fold<int>(
      0,
      (runningTotal, item) => runningTotal + parseMoney(item.amount.text)!,
    );
    if (_items.isNotEmpty && itemTotal != total) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Items and total differ'),
          content: Text(
            'Items add up to ${displayMoney(widget.household.currency, itemTotal)}, but the receipt total is ${displayMoney(widget.household.currency, total)}. This may be tax, a discount, or an OCR mistake. Save this total?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save this total'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveExpense(
        household: widget.household,
        id: _id,
        merchant: _merchant.text.trim(),
        payer: _payer,
        date: _date,
        items: _items
            .map(
              (item) => ExpenseItem(
                item.name.text.trim(),
                parseMoney(item.amount.text)!,
              ),
            )
            .toList(),
        total: total,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.fromReceipt ? 'Review receipt' : 'Add expense'),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.fromReceipt)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Check every field before saving. OCR can miss or misread text. Only extracted data is shared; the receipt image stays on this device.',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Latin-script receipts are supported. Dates with day first are assumed when the year is last. For other scripts or formats, enter corrections manually.',
                        ),
                        if (widget.draft.rawText.isEmpty)
                          const Text(
                            'No text was detected. Enter the details below.',
                          ),
                        if (widget.draft.rawText.isNotEmpty)
                          ExpansionTile(
                            title: const Text('View detected text'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(widget.draft.rawText),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _merchant,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Merchant / expense name',
                ),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ||
                        value!.trim().length > 100
                    ? 'Enter a name up to 100 characters.'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _payer,
                decoration: const InputDecoration(labelText: 'Who paid?'),
                items: widget.household.members
                    .map(
                      (id) => DropdownMenuItem(
                        value: id,
                        child: Text(widget.household.name(id)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _payer = value!),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(DateFormat.yMMMd().format(_date)),
              ),
              const SizedBox(height: 20),
              Text(
                'Items (optional)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Use each line’s total price, including quantity. Up to 100 items.',
              ),
              for (var i = 0; i < _items.length; i++)
                Padding(
                  key: ObjectKey(_items[i]),
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _items[i].name,
                          maxLength: 100,
                          decoration: InputDecoration(
                            labelText: 'Item ${i + 1}',
                          ),
                          validator: (value) =>
                              (value?.trim().isEmpty ?? true) ||
                                  value!.trim().length > 100
                              ? 'Use 1–100 characters.'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _items[i].amount,
                          decoration: const InputDecoration(labelText: 'Price'),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) => parseMoney(value ?? '') == null
                              ? 'Invalid price'
                              : null,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove item',
                        onPressed: () {
                          final item = _items[i];
                          setState(() => _items.removeAt(i));
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => item.dispose(),
                          );
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: _items.length < 100
                    ? () => setState(() => _items.add(_ItemFields()))
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
              if (_items.isNotEmpty)
                TextButton(
                  onPressed: () {
                    var sum = 0;
                    for (final item in _items) {
                      final price = parseMoney(item.amount.text);
                      if (price == null) {
                        setState(
                          () => _error = 'Enter valid item prices first.',
                        );
                        return;
                      }
                      sum += price;
                    }
                    _total.text = moneyInput(sum);
                  },
                  child: const Text('Use sum of item prices as total'),
                ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _total,
                decoration: InputDecoration(
                  labelText: 'Total (${widget.household.currency})',
                  helperText: 'This total determines your shared spending.',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final amount = parseMoney(value ?? '');
                  return amount == null || amount <= 0
                      ? 'Enter a total greater than zero (up to 10,000,000).'
                      : null;
                },
              ),
              if (widget.fromReceipt)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reviewed,
                  onChanged: (value) => setState(() => _reviewed = value!),
                  title: const Text(
                    'I reviewed the merchant, date, payer, items and total.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _saving ? 'Saving — waiting for sync…' : 'Save expense',
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Keep this screen open. If offline, saving completes when the connection returns.',
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}

class ExpenseDetails extends StatefulWidget {
  const ExpenseDetails({
    super.key,
    required this.expense,
    required this.household,
    required this.repository,
  });
  final Expense expense;
  final Household household;
  final HouseholdRepository repository;
  @override
  State<ExpenseDetails> createState() => _ExpenseDetailsState();
}

class _ExpenseDetailsState extends State<ExpenseDetails> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _watchItems() => widget
      .repository
      .db
      .collection('households')
      .doc(widget.household.id)
      .collection('expenses')
      .doc(widget.expense.id)
      .collection('items')
      .orderBy('index')
      .snapshots();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _items = _watchItems();
  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final household = widget.household;
    return Scaffold(
      appBar: AppBar(title: const Text('Expense details')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            expense.merchant,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(DateFormat.yMMMMd().format(expense.date)),
          Text('Paid by ${household.name(expense.payer)}'),
          Text('Added by ${household.name(expense.creator)}'),
          const Divider(height: 32),
          if (expense.itemCount == 0)
            const Text('No item breakdown was added.')
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _items,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return RetryMessage(
                    error: snapshot.error!,
                    retry: () => setState(() => _items = _watchItems()),
                  );
                }
                if (!snapshot.hasData) {
                  return const Busy(message: 'Loading items…');
                }
                if (snapshot.data!.docs.length != expense.itemCount) {
                  return const Text(
                    'Item details are incomplete. Reconnect to load all items.',
                  );
                }
                return Column(
                  children: [
                    for (final item in snapshot.data!.docs)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.data()['name'] as String),
                        trailing: Text(
                          displayMoney(
                            household.currency,
                            item.data()['amount'] as int,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          const Divider(height: 32),
          Text(
            'Total: ${displayMoney(household.currency, expense.total)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}
