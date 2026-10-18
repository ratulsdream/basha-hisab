import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  static final instance = AppPreferences();
  String language = 'en';
  ThemeMode theme = ThemeMode.system;
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    language = prefs.getString('ui.language') == 'bn' ? 'bn' : 'en';
    theme = ThemeMode.values.firstWhere(
      (m) => m.name == prefs.getString('ui.theme'),
      orElse: () => ThemeMode.system,
    );
    notifyListeners();
  }

  Future<void> update({String? locale, ThemeMode? mode}) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale != null && ['en', 'bn'].contains(locale)) {
      await prefs.setString('ui.language', locale);
      language = locale;
    }
    if (mode != null) {
      await prefs.setString('ui.theme', mode.name);
      theme = mode;
    }
    notifyListeners();
  }
}

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF087F6A),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamilyFallback: const ['BashaBengali', 'BashaGreek'],
    colorScheme: colors,
    brightness: brightness,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF111B19)
        : const Color(0xFFF5F9F7),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
  );
}
