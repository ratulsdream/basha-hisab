import 'package:basha_hisab/l10n/app_text.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data.dart';

import '../../widgets/common.dart';
import '../groups/groups_screen.dart';
import 'auth_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    initialData: FirebaseAuth.instance.currentUser,
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
      if (snapshot.connectionState == ConnectionState.waiting &&
          snapshot.data == null) {
        return const Scaffold(body: Busy());
      }
      return snapshot.data == null
          ? const AuthScreen()
          : GroupsScreen(key: ValueKey(snapshot.data!.uid));
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
  late final _accountService = AccountService(FirebaseAuth.instance);
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
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = _accountService;
      if (_register) {
        await service.register(_email.text, _password.text);
      } else {
        await service.signIn(_email.text, _password.text);
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter your email above to reset your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await authRequest(
        () => FirebaseAuth.instance.sendPasswordResetEmail(
          email: normalizeEmail(_email.text),
        ),
      ).timeout(const Duration(seconds: 20));
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
                    AppText(
                      'BashaHisab',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const Text(
                      'One home. Two roommates. Clear expenses.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    AppText(
                      _register ? 'Create your account' : 'Welcome back',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: tr(context, 'Email'),
                      ),
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
                        labelText: tr(context, 'Password'),
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
                        child: AppText(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: AppText(
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
                        child: const AppText('Forgot password?'),
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
