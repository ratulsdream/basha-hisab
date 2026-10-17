import 'dart:convert';
import 'package:crypto/crypto.dart';

const notificationKinds = [
  'expense',
  'shopping',
  'stock',
  'recurring',
  'settlement',
  'budget',
];

class NotificationSettings {
  NotificationSettings({
    this.enabled = false,
    this.remote = false,
    this.zone = 'Europe/Nicosia',
    Map<String, bool>? kinds,
  }) : kinds = {for (final k in notificationKinds) k: kinds?[k] ?? false};
  final bool enabled, remote;
  final String zone;
  final Map<String, bool> kinds;
  bool allows(String kind) => enabled && kinds[kind] == true;
  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'remote': remote,
    'zone': zone,
    'kinds': kinds,
  };
  factory NotificationSettings.fromMap(Map<String, dynamic> d) =>
      NotificationSettings(
        enabled: d['enabled'] == true,
        remote: d['remote'] == true,
        zone: d['zone'] as String? ?? 'Europe/Nicosia',
        kinds: Map<String, bool>.from(d['kinds'] as Map? ?? {}),
      );
  String encode() => jsonEncode(toMap());
}

int notificationId(String event) {
  final bytes = sha256.convert(utf8.encode(event)).bytes;
  return ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
      0x7fffffff;
}
