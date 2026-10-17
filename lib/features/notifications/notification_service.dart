import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    hide NotificationSettings;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'package:crypto/crypto.dart';
import '../../data.dart';
import 'notification_settings.dart';

const remoteNotificationsEnabled = bool.fromEnvironment(
  'V3_REMOTE_NOTIFICATIONS',
  defaultValue: false,
);
const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'home_updates',
    'Home updates',
    channelDescription: 'Updates you enabled for your homes',
    icon: 'ic_notification',
  ),
  iOS: DarwinNotificationDetails(),
);
Future<FlutterLocalNotificationsPlugin> notificationPlugin() async {
  zones.initializeTimeZones();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
  return plugin;
}

/// Data-only push. Late messages after sign-out/leave are dropped; no private data in lock-screen text.
@pragma('vm:entry-point')
Future<void> notificationBackground(RemoteMessage message) async {
  await Firebase.initializeApp();
  await deliverRemote(message);
}

Future<void> deliverRemote(RemoteMessage message) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final d = message.data;
  if (uid == null ||
      d['uid'] != uid ||
      !notificationKinds.contains(d['kind']) ||
      d['groupId'] == null ||
      d['eventId'] == null) {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final settings = NotificationSettings.fromMap(
    jsonDecode(prefs.getString('notifications:$uid') ?? '{}')
        as Map<String, dynamic>,
  );
  if (!remoteNotificationsEnabled ||
      !settings.remote ||
      !settings.allows(d['kind']!)) {
    return;
  }
  try {
    final currentPreferences = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('preferences')
        .doc('notifications')
        .get(const GetOptions(source: Source.server));
    final current = NotificationSettings.fromMap(
      currentPreferences.data() ?? {},
    );
    if (!current.remote || !current.allows(d['kind'] as String)) return;
    final home = await FirebaseFirestore.instance
        .collection('households')
        .doc(d['groupId'])
        .get(const GetOptions(source: Source.server));
    if (!(home.data()?['memberIds'] as List? ?? []).contains(uid)) return;
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    final event = d['eventId']! as String;
    final seen = prefs.getStringList('notification-events:$uid') ?? [];
    if (seen.contains(event)) return;
    await prefs.setStringList(
      'notification-events:$uid',
      [...seen, event].reversed.take(500).toList().reversed.toList(),
    );
    await (await notificationPlugin()).show(
      notificationId(event),
      'BashaHisab',
      'There is an update in one of your homes.',
      _details,
    );
  } catch (_) {
    /* Do not expose an old group's data when membership cannot be verified. */
  }
}

class HomeNotifications {
  HomeNotifications(this.repository);
  final HouseholdRepository repository;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Map<String, List<StreamSubscription<dynamic>>> _groups = {};
  FlutterLocalNotificationsPlugin? _plugin;
  bool stopped = false;
  Future<void> _reminderWork = Future.value();
  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final doc = await repository.profile
          .collection('preferences')
          .doc('notifications')
          .get()
          .timeout(const Duration(seconds: 3));
      if (doc.exists) {
        await prefs.setString(
          'notifications:${repository.uid}',
          NotificationSettings.fromMap(doc.data()!).encode(),
        );
      }
    } catch (_) {}
    if (stopped) return;
    _plugin = await notificationPlugin();
    if (stopped) return;
    _subscriptions.add(
      repository.profile
          .collection('preferences')
          .doc('notifications')
          .snapshots()
          .listen((doc) async {
            try {
              if (stopped ||
                  doc.metadata.isFromCache ||
                  doc.metadata.hasPendingWrites) {
                return;
              }
              final next = NotificationSettings.fromMap(doc.data() ?? {});
              final prior = _settings(prefs);
              await prefs.setString(
                'notifications:${repository.uid}',
                next.encode(),
              );
              if (!next.enabled ||
                  notificationKinds.any(
                    (kind) => prior.allows(kind) && !next.allows(kind),
                  )) {
                _reminderWork = _reminderWork.then((_) async {
                  await _plugin?.cancelAll();
                });
                await _reminderWork;
              }
            } catch (_) {}
          }, onError: (Object _) {}),
    );
    _subscriptions.add(
      repository.watchMemberships().listen((snapshot) {
        final ids = snapshot.docs.map((d) => d.id).toSet();
        for (final old
            in _groups.keys.where((id) => !ids.contains(id)).toList()) {
          for (final sub in _groups.remove(old)!) {
            unawaited(sub.cancel());
          }
          _reminderWork = _reminderWork
              .then((_) => _cancelReminders(old, prefs))
              .catchError((Object _) {});
        }
        for (final id in ids.where((id) => !_groups.containsKey(id))) {
          _watchGroup(id, prefs);
        }
      }, onError: (Object _) {}),
    );
    if (remoteNotificationsEnabled) {
      _subscriptions.add(FirebaseMessaging.onMessage.listen(deliverRemote));
      _subscriptions.add(
        FirebaseMessaging.instance.onTokenRefresh.listen(
          (token) => unawaited(
            registerToken(repository, token).catchError((Object _) {}),
          ),
          onError: (Object _) {},
        ),
      );
    }
  }

  NotificationSettings _settings(SharedPreferences p) =>
      NotificationSettings.fromMap(
        jsonDecode(p.getString('notifications:${repository.uid}') ?? '{}')
            as Map<String, dynamic>,
      );
  Future<void> _show(
    String group,
    String kind,
    String event,
    SharedPreferences prefs,
  ) async {
    if (stopped ||
        repository.auth.currentUser?.uid != repository.uid ||
        !_settings(prefs).allows(kind)) {
      return;
    }
    final home = await repository.db
        .collection('households')
        .doc(group)
        .get(const GetOptions(source: Source.server));
    if (stopped ||
        !(home.data()?['memberIds'] as List? ?? []).contains(repository.uid)) {
      return;
    }
    final key = 'notification-events:${repository.uid}';
    final seen = prefs.getStringList(key) ?? [];
    if (seen.contains(event)) return;
    await prefs.setStringList(
      key,
      [...seen, event].reversed.take(500).toList().reversed.toList(),
    );
    if (stopped) return;
    await _plugin?.show(
      notificationId(event),
      'BashaHisab',
      '${kind[0].toUpperCase()}${kind.substring(1)} update in your home. Open the app to review.',
      _details,
    );
  }

  void _watchGroup(String id, SharedPreferences prefs) {
    final subscriptions = <StreamSubscription<dynamic>>[];
    _groups[id] = subscriptions;
    final group = repository.db.collection('households').doc(id);
    void watch(
      String collection,
      String kind,
      bool Function(Map<String, dynamic>) relevant,
    ) {
      var initialized = false;
      final previous = <String, int>{};
      subscriptions.add(
        group.collection(collection).snapshots().listen((s) {
          if (s.metadata.isFromCache || s.metadata.hasPendingWrites) return;
          if (!initialized) {
            initialized = true;
            if (collection == 'stock') {
              for (final d in s.docs) {
                previous[d.id] = d.data()['quantityMilli'] as int? ?? 0;
              }
            }
            return;
          }
          for (final change in s.docChanges) {
            final data = change.doc.data()!;
            if (change.type == DocumentChangeType.removed) continue;
            if (collection == 'expenses' &&
                change.type != DocumentChangeType.added) {
              continue;
            }
            if (collection == 'stock') {
              final before = previous[change.doc.id];
              previous[change.doc.id] = data['quantityMilli'] as int? ?? 0;
              if (before == null ||
                  before <= (data['lowStockMilli'] as int? ?? -1)) {
                continue;
              }
            }
            if (collection != 'stock' &&
                (data['updatedBy'] == repository.uid ||
                    data['createdBy'] == repository.uid)) {
              continue;
            }
            if (relevant(data)) {
              unawaited(
                _show(
                  id,
                  kind,
                  '$id/$collection/${change.doc.id}/${data['revision'] ?? 0}',
                  prefs,
                ).catchError((Object _) {}),
              );
            }
          }
        }, onError: (Object _) {}),
      );
    }

    watch('expenses', 'expense', (d) => d['scope'] != 'personal');
    watch('shopping', 'shopping', (_) => true);
    watch(
      'stock',
      'stock',
      (d) =>
          (d['quantityMilli'] as int? ?? 0) <=
          (d['lowStockMilli'] as int? ?? -1),
    );
    // Changes in spending re-evaluate current budget; event key prevents repeated alerts.
    subscriptions.add(
      group.collection('expenses').snapshots().listen((s) async {
        try {
          if (s.metadata.isFromCache || s.metadata.hasPendingWrites) return;
          final now = DateTime.now();
          final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
          final budget = (await group.collection('budgets').doc(month).get())
              .data();
          final limit = budget?['total'] as int? ?? 0;
          final spent = s.docs
              .where(
                (d) => d.data()['month'] == month && d.data()['voided'] != true,
              )
              .fold<int>(
                0,
                (acc, d) =>
                    acc +
                    (d.data()['kind'] == 'refund' ? -1 : 1) *
                        (d.data()['total'] as int),
              );
          if (limit > 0 && spent * 100 >= limit * 80) {
            await _show(
              id,
              'budget',
              '$id/budget/$month/${spent >= limit ? 100 : 80}',
              prefs,
            );
          }
        } catch (_) {}
      }, onError: (Object _) {}),
    );
    subscriptions.add(
      group.collection('recurring').snapshots().listen((s) {
        _reminderWork = _reminderWork.then((_) async {
          try {
            final settings = _settings(prefs);
            await _cancelReminders(id, prefs);
            if (stopped) return;
            final now = tz.TZDateTime.now(tz.getLocation(settings.zone));
            final ids = <int>[];
            for (final d
                in s.docs
                    .where(
                      (d) =>
                          settings.allows('recurring') &&
                          d.data()['enabled'] == true,
                    )
                    .take(20)) {
              var date = tz.TZDateTime(
                now.location,
                now.year,
                now.month,
                (d.data()['day'] as int).clamp(
                  1,
                  DateTime(now.year, now.month + 1, 0).day,
                ),
                9,
              );
              if (!date.isAfter(now)) {
                date = tz.TZDateTime(
                  now.location,
                  now.year,
                  now.month + 1,
                  (d.data()['day'] as int).clamp(
                    1,
                    DateTime(now.year, now.month + 2, 0).day,
                  ),
                  9,
                );
              }
              final event = notificationId(
                '${repository.uid}/$id/recurring/${d.id}',
              );
              if (((await _plugin?.pendingNotificationRequests())?.length ??
                      0) >=
                  48) {
                break;
              }
              if (stopped || !_groups.containsKey(id)) break;
              ids.add(event);
              await _plugin?.zonedSchedule(
                event,
                'BashaHisab',
                'A recurring expense is due for review. Nothing has been saved automatically.',
                date,
                _details,
                androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              );
            }
            if (settings.allows('settlement') &&
                !stopped &&
                _groups.containsKey(id) &&
                ((await _plugin?.pendingNotificationRequests())?.length ?? 0) <
                    48) {
              final event = notificationId('${repository.uid}/$id/settlement');
              ids.add(event);
              await _plugin?.zonedSchedule(
                event,
                'BashaHisab',
                'Review your home’s monthly settlement.',
                tz.TZDateTime(now.location, now.year, now.month + 1, 1, 10),
                _details,
                androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              );
            }
            await prefs.setStringList(
              'reminders:${repository.uid}:$id',
              ids.map((i) => '$i').toList(),
            );
          } catch (_) {}
        });
      }, onError: (Object _) {}),
    );
  }

  Future<void> _cancelReminders(String id, SharedPreferences prefs) async {
    final uid = repository.auth.currentUser?.uid;
    if (uid == null) return;
    for (final value in prefs.getStringList('reminders:$uid:$id') ?? []) {
      await _plugin?.cancel(int.parse(value));
    }
    await prefs.remove('reminders:$uid:$id');
  }

  Future<void> stop() async {
    stopped = true;
    for (final sub in [..._subscriptions, ..._groups.values.expand((x) => x)]) {
      await sub.cancel();
    }
    await _reminderWork;
    // No notifications may remain scheduled across account switches.
    await _plugin?.cancelAll();
  }
}

Future<void> registerToken(HouseholdRepository repo, [String? token]) async {
  if (!remoteNotificationsEnabled) return;
  final prefs = await SharedPreferences.getInstance();
  final settings = NotificationSettings.fromMap(
    jsonDecode(prefs.getString('notifications:${repo.uid}') ?? '{}')
        as Map<String, dynamic>,
  );
  if (!settings.enabled || !settings.remote) return;
  token ??= await FirebaseMessaging.instance.getToken();
  if (token == null) return;
  final id = sha256.convert(utf8.encode(token)).toString();
  await repo.profile.collection('devices').doc(id).set({
    'token': token,
    'platform': Platform.isIOS ? 'ios' : 'android',
    'enabled': true,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
