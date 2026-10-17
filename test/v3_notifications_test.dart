import 'package:flutter_test/flutter_test.dart';
import 'package:basha_hisab/features/notifications/notification_settings.dart';

void main() {
  test('all notifications are opt-in and round-trip per-kind choices', () {
    final defaults = NotificationSettings();
    for (final k in notificationKinds) {
      expect(defaults.allows(k), false);
    }
    final enabled = NotificationSettings(
      enabled: true,
      kinds: {'expense': true},
    );
    final restored = NotificationSettings.fromMap(enabled.toMap());
    expect(restored.allows('expense'), true);
    expect(restored.allows('shopping'), false);
    expect(restored.remote, false);
    expect(restored.zone, 'Europe/Nicosia');
  });
  test(
    'notification identifiers stable and namespaced for accounts and groups',
    () {
      expect(notificationId('a/home/1'), notificationId('a/home/1'));
      expect(notificationId('a/home/1'), isNot(notificationId('b/home/1')));
      expect(notificationId('a/home/1'), isNot(notificationId('a/other/1')));
      expect(notificationId('a/home/1'), inInclusiveRange(0, 0x7fffffff));
    },
  );
}
