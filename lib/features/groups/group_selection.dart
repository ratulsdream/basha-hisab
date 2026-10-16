import 'package:shared_preferences/shared_preferences.dart';

/// Per-account selection avoids opening another signed-in person's last home.
class GroupSelection {
  GroupSelection(this.preferences, this.uid);
  final SharedPreferences preferences;
  final String uid;
  String get _key => 'v2.lastGroup.$uid';
  String? get selected => preferences.getString(_key);
  Future<void> select(String id) async {
    await preferences.setString(_key, id);
  }

  Future<void> clear() async {
    await preferences.remove(_key);
  }

  String? resolve(Iterable<String> memberships) =>
      memberships.contains(selected) ? selected : null;
}
