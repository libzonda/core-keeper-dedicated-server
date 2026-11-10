import 'package:flutter/foundation.dart';

const String defaultAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'v0.1.7');

class AppVersion {
  static String format(String v) {
    final trimmed = v.trim();
    if (trimmed.isEmpty) return defaultAppVersion;
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      return 'v${trimmed.substring(1)}';
    }
    return 'v$trimmed';
  }

  static final ValueNotifier<String> notifier = ValueNotifier<String>(format(defaultAppVersion));

  static String get current => notifier.value;

  static void update(String newVersion) {
    if (newVersion.isNotEmpty) {
      final formatted = format(newVersion);
      if (notifier.value != formatted) {
        notifier.value = formatted;
      }
    }
  }
}


