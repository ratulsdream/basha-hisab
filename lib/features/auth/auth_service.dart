import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

String normalizeEmail(String value) => value.trim().toLowerCase();

/// Only retry completed transient failures. Timed-out native operations cannot
/// be cancelled, so AccountService keeps them guarded until they actually finish.
Future<T> authRequest<T>(Future<T> Function() operation) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await operation();
    } on FirebaseAuthException catch (error) {
      if (error.code != 'network-request-failed' || attempt >= 1) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
}

/// Auth is authoritative. Profile recovery runs in the signed-in UI shell.
class AccountService {
  AccountService(this.auth);
  final FirebaseAuth auth;
  Future<void>? _pending;
  Future<void> _run(Future<void> Function() operation) {
    if (_pending != null) {
      throw StateError(
        'Your previous sign-in request is still finishing. Please wait a moment.',
      );
    }
    final pending = _pending = operation();
    unawaited(
      pending.then<void>(
        (_) {
          _pending = null;
        },
        onError: (Object _, StackTrace _) {
          _pending = null;
        },
      ),
    );
    return pending.timeout(const Duration(seconds: 20));
  }

  Future<void> register(String email, String password) => _run(() async {
    final normalized = normalizeEmail(email);
    try {
      await authRequest(
        () => auth.createUserWithEmailAndPassword(
          email: normalized,
          password: password,
        ),
      );
    } on FirebaseAuthException catch (error) {
      // Recover if a previous registration created Auth but lost its response.
      if (error.code != 'email-already-in-use') rethrow;
      await authRequest(
        () => auth.signInWithEmailAndPassword(
          email: normalized,
          password: password,
        ),
      );
    }
  });
  Future<void> signIn(String email, String password) => _run(() async {
    await authRequest(
      () => auth.signInWithEmailAndPassword(
        email: normalizeEmail(email),
        password: password,
      ),
    );
  });
}
