import 'package:flutter/material.dart';
import '../../l10n/app_text.dart';
import 'app_preferences.dart';

class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppPreferences.instance,
    builder: (context, _) {
      final prefs = AppPreferences.instance;
      return Scaffold(
        appBar: AppBar(title: const AppText('Language & appearance')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const AppText(
              'Language',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            RadioGroup<String>(
              groupValue: prefs.language,
              onChanged: (v) => prefs.update(locale: v),
              child: Column(
                children: [
                  for (final lang in [('en', 'English'), ('bn', 'বাংলা')])
                    RadioListTile<String>(title: Text(lang.$2), value: lang.$1),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const AppText(
              'Appearance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            RadioGroup<ThemeMode>(
              groupValue: prefs.theme,
              onChanged: (v) => prefs.update(mode: v),
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      title: AppText(switch (mode) {
                        ThemeMode.system => 'System',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      }),
                      value: mode,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: AppText(
                  'Receipt photos stay on your phone. Only reviewed expense data is shared with your home.',
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
