import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';

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
