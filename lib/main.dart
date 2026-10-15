import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? initializationError;
  try {
    // Native Firebase configs are injected by the developer or CI, never Storage.
    await Firebase.initializeApp();
  } catch (error) {
    initializationError = error;
  }
  runApp(BashaHisabApp(initializationError: initializationError));
}

class BashaHisabApp extends StatelessWidget {
  const BashaHisabApp({super.key, this.initializationError});
  final Object? initializationError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BashaHisab',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F6A)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 6)),
    ),
    home: initializationError == null
        ? const AuthGate()
        : const SetupErrorScreen(),
  );
}

class SetupErrorScreen extends StatelessWidget {
  const SetupErrorScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('BashaHisab')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_outlined, size: 52),
            SizedBox(height: 16),
            Text('Firebase setup needed', style: TextStyle(fontSize: 24)),
            SizedBox(height: 12),
            Text(
              'The app could not connect to its Firebase configuration. Check the platform configuration files, rebuild the app, and try again.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
