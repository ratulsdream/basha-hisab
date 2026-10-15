import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basha_hisab/main.dart';
import 'package:basha_hisab/screens.dart';

void main() {
  testWidgets('missing Firebase config has an actionable screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      BashaHisabApp(initializationError: Exception('missing config')),
    );
    expect(find.text('Firebase setup needed'), findsOneWidget);
    expect(find.textContaining('rebuild the app'), findsOneWidget);
  });
  testWidgets('sign in validates email and password before network calls', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email.'), findsOneWidget);
    expect(find.text('Use at least 6 characters.'), findsOneWidget);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    expect(find.text('Create your account'), findsOneWidget);
  });
}
