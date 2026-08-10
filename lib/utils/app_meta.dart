import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Keep in sync with `version` in pubspec.yaml (major.minor.patch).
class AppMeta {
  AppMeta._();

  static const String version = '1.0.1';
  static const String _deviceIdKey = 'device_install_id';

  static Future<String> deviceInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(_deviceIdKey, id);
    return id;
  }
}
