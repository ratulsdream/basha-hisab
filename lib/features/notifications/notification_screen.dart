import 'package:basha_hisab/l10n/app_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    hide NotificationSettings;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data.dart';
import '../../widgets/common.dart';
import 'notification_settings.dart';
import 'notification_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key, required this.repository});
  final HouseholdRepository repository;
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  NotificationSettings settings = NotificationSettings();
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final doc = await widget.repository.profile
          .collection('preferences')
          .doc('notifications')
          .get();
      if (mounted) {
        setState(
          () => settings = NotificationSettings.fromMap(doc.data() ?? {}),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final repo = widget.repository;
      if (settings.enabled) {
        final plugin = await notificationPlugin();
        final android = plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final ios = plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final allowed =
            await android?.requestNotificationsPermission() ??
            await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
        if (!allowed) {
          throw StateError(
            'Notifications are disabled in phone settings. Enable them there and retry.',
          );
        }
      }
      await repo.profile.collection('preferences').doc('notifications').set({
        ...settings.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notifications:${repo.uid}', settings.encode());
      if (!settings.enabled) await (await notificationPlugin()).cancelAll();
      if (remoteNotificationsEnabled) {
        if (settings.enabled && settings.remote) {
          await FirebaseMessaging.instance.setAutoInitEnabled(true);
          await registerToken(repo);
        } else {
          final devices = await repo.profile.collection('devices').get();
          for (final d in devices.docs) {
            await d.reference.update({
              'enabled': false,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
          await FirebaseMessaging.instance.deleteToken();
          await FirebaseMessaging.instance.setAutoInitEnabled(false);
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void update({
    bool? enabled,
    bool? remote,
    String? zone,
    Map<String, bool>? kinds,
  }) => setState(
    () => settings = NotificationSettings(
      enabled: enabled ?? settings.enabled,
      remote: remote ?? settings.remote,
      zone: zone ?? settings.zone,
      kinds: kinds ?? settings.kinds,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Notifications')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Choose which reminders you want. Permissions are requested only when you save enabled settings. Local updates work while the app is open; scheduled reminders need phone permission. Reopen My Groups after saving to refresh reminder schedules.',
        ),
        if (busy) const LinearProgressIndicator(),
        SwitchListTile(
          title: const AppText('Enable notifications'),
          value: settings.enabled,
          onChanged: busy ? null : (v) => update(enabled: v),
        ),
        for (final kind in notificationKinds)
          SwitchListTile(
            title: Text(kind),
            value: settings.kinds[kind]!,
            onChanged: busy
                ? null
                : (v) => update(kinds: {...settings.kinds, kind: v}),
          ),
        DropdownButtonFormField<String>(
          initialValue: settings.zone,
          decoration: InputDecoration(
            labelText: tr(context, 'Reminder time zone'),
          ),
          items: [
            'Europe/Nicosia',
            'Europe/Athens',
            'Europe/London',
            'Asia/Dhaka',
            'UTC',
          ].map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
          onChanged: busy ? null : (v) => update(zone: v),
        ),
        if (remoteNotificationsEnabled)
          SwitchListTile(
            title: const Text('Background push updates'),
            subtitle: const Text(
              'Requires configured Firebase Functions and APNs for iPhone.',
            ),
            value: settings.remote,
            onChanged: busy ? null : (v) => update(remote: v),
          ),
        if (!remoteNotificationsEnabled)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Background push delivery awaits server and Apple APNs configuration. It is disabled in this build.',
            ),
          ),
        FilledButton(
          onPressed: busy ? null : save,
          child: const AppText('Save preferences'),
        ),
      ],
    ),
  );
}
