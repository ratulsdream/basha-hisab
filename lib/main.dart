import 'package:basha_hisab/l10n/app_text.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/shell/app_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'features/notifications/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final name in ['Tesseract', 'Leptonica', 'Tesseract4Android']) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/licenses/$name.txt'));
    }
    yield LicenseEntryWithLineBreaks([
      'Noto Sans Bengali',
    ], await rootBundle.loadString('assets/fonts/NOTO-LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'DejaVu Sans',
    ], await rootBundle.loadString('assets/fonts/LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'tessdata_fast Greek and English',
    ], await rootBundle.loadString('assets/tessdata/LICENSE'));
  });
  await AppPreferences.instance.load();
  Object? initializationError;
  try {
    // Native Firebase configs are injected by the developer or CI, never Storage.
    await Firebase.initializeApp();
    if (remoteNotificationsEnabled) {
      FirebaseMessaging.onBackgroundMessage(notificationBackground);
    }
  } catch (error) {
    initializationError = error;
  }
  runApp(BashaHisabApp(initializationError: initializationError));
}

class BashaHisabApp extends StatelessWidget {
  const BashaHisabApp({super.key, this.initializationError});
  final Object? initializationError;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppPreferences.instance,
    builder: (context, _) => MaterialApp(
      title: 'BashaHisab',
      debugShowCheckedModeBanner: false,
      locale: Locale(AppPreferences.instance.language),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: AppPreferences.instance.theme,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: initializationError == null
          ? const AuthGate()
          : const SetupErrorScreen(),
    ),
  );
}

class SetupErrorScreen extends StatelessWidget {
  const SetupErrorScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('BashaHisab')),
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
